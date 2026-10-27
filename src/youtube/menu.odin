package youtube

import "../http"
import "../model"
import "core:encoding/json"
import "core:strings"

// Only copy the request fields documented by YouTube.js's endpoint builders.
// Never retain tracking data or the stream configuration in watch endpoints.
Card_Request :: struct {
	ctx:             struct {
		client: Client_Context,
	} `json:"context"`,
	playlist_id:     string `json:"playlistId,omitempty"`,
	actions:         json.Array `json:",omitempty"`,
	video_ids:       []string `json:"videoIds,omitempty"`,
	feedback_tokens: []string `json:"feedbackTokens,omitempty"`,
}

card_action :: proc(label: string, endpoint: json.Value) -> (action: model.Card_Action, ok: bool) {
	if label == "" {return}
	request := Card_Request {
		ctx = {
			client = {clientName = "TVHTML5", clientVersion = TV_VERSION, hl = "en", gl = "US"},
		},
	}
	if browse := field(endpoint, "browseEndpoint"); browse != nil {
		id, _ := field(browse, "browseId").(json.String)
		if id == "" {return}
		action.kind = .Browse
		action.target = strings.clone(string(id))
	} else if edit := field(endpoint, "playlistEditEndpoint"); edit != nil {
		id, _ := field(edit, "playlistId").(json.String)
		actions, _ := field(edit, "actions").(json.Array)
		if id == "" || len(actions) == 0 {return}
		action.kind = .Edit_Playlist
		action.target = strings.clone(string(id))
		request.playlist_id, request.actions = string(id), actions
	} else if feedback := field(endpoint, "feedbackEndpoint"); feedback != nil {
		token, _ := field(feedback, "feedbackToken").(json.String)
		if token == "" {return}
		action.kind = .Feedback
		request.feedback_tokens = []string{string(token)}
	} else {
		playlist := field(endpoint, "addToPlaylistEndpoint")
		if playlist == nil {playlist = field(endpoint, "addToPlaylistServiceEndpoint")}
		id, _ := field(playlist, "videoId").(json.String)
		if !video_id_valid(string(id)) {return}
		action.kind = .Playlists
		request.video_ids = []string{string(id)}
	}
	if action.kind == .Edit_Playlist || action.kind == .Feedback || action.kind == .Playlists {
		bytes, error := json.marshal(request)
		if error != nil {return {}, false}
		// The action owns the marshalled bytes until its payload is deleted.
		action.payload = string(bytes)
	}
	action.label = strings.clone(label)
	return action, true
}

parse_card_actions :: proc(value: json.Value) -> (actions: [dynamic]model.Card_Action) {
	#partial switch item in value {
	case json.Array:
		for child in item {
			actions = parse_card_actions(child)
			if len(actions) > 0 {return}
		}
	case json.Object:
		if menu := item["menuRenderer"]; menu != nil {
			items, _ := field(menu, "items").(json.Array)
			for entry in items {
				renderer := field(entry, "menuNavigationItemRenderer")
				endpoint := field(renderer, "navigationEndpoint")
				if renderer == nil {
					renderer = field(entry, "menuServiceItemRenderer")
					endpoint = field(renderer, "serviceEndpoint")
				}
				label := text(field(renderer, "text"))
				defer delete(label)
				if label == "Hide" {continue}
				if action, ok := card_action(label, endpoint); ok {append(&actions, action)}
			}
			return
		}
		for _, child in item {
			actions = parse_card_actions(child)
			if len(actions) > 0 {return}
		}
	}
	return
}

playlist_actions :: proc(value: json.Value, actions: ^[dynamic]model.Card_Action) {
	#partial switch item in value {
	case json.Array:
		for child in item {playlist_actions(child, actions)}
	case json.Object:
		if option := item["playlistAddToOptionRenderer"]; option != nil {
			membership, _ := field(option, "containsSelectedVideos").(json.String)
			label := text(field(option, "title"))
			defer delete(label)
			remove := membership == "ALL"
			endpoint := field(
				option,
				remove ? "removeFromPlaylistServiceEndpoint" : "addToPlaylistServiceEndpoint",
			)
			choice := strings.concatenate({remove ? "Remove from " : "Add to ", label})
			defer delete(choice)
			if action, ok := card_action(choice, endpoint); ok {append(actions, action)}
			return
		}
		for _, child in item {playlist_actions(child, actions)}
	}
	return
}

perform_card_action :: proc(
	client: ^http.Client,
	action: model.Card_Action,
) -> (
	actions: [dynamic]model.Card_Action,
	error: Error,
) {
	if access_token == "" {return nil, .Unavailable}
	route: string
	switch action.kind {
	case .Edit_Playlist:
		route = "browse/edit_playlist"
	case .Feedback:
		route = "feedback"
	case .Playlists:
		route = "playlist/get_add_to_playlist"
	case .Browse:
		return nil, .Invalid_Response
	}
	response, err := api_post(client, route, transmute([]u8)action.payload, .TV)
	if err != .None {return nil, err}
	defer delete(response.body)
	value, parse_error := json.parse(string(response.body[:]))
	if parse_error != .None {return nil, .Invalid_Response}
	defer json.destroy_value(value)
	if field(value, "error") != nil {return nil, .Unavailable}
	status, _ := field(value, "status").(json.String)
	if status != "" && status != "STATUS_SUCCEEDED" {return nil, .Unavailable}
	if action.kind == .Playlists {
		playlist_actions(value, &actions)
		if len(actions) == 0 {return nil, .Unavailable}
	}
	return actions, .None
}
