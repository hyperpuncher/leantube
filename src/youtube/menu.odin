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
	panel_id:        string `json:"panelId,omitempty"`,
	params:          string `json:",omitempty"`,
	actions:         json.Array `json:",omitempty"`,
	video_ids:       []string `json:"videoIds,omitempty"`,
	feedback_tokens: []string `json:"feedbackTokens,omitempty"`,
}

card_action :: proc(label: string, endpoint: json.Value) -> (action: model.Card_Action, ok: bool) {
	if label == "" {return}
	if executor := field(endpoint, "commandExecutorCommand"); executor != nil {
		commands, _ := field(executor, "commands").(json.Array)
		for command in commands {
			if nested, valid := card_action(label, command); valid {return nested, true}
		}
		return
	}
	request := Card_Request {
		ctx = {
			client = {clientName = "TVHTML5", clientVersion = TV_VERSION, hl = "en", gl = "US"},
		},
	}
	if panel := field(endpoint, "showEngagementPanelEndpoint"); panel != nil {
		id, _ := field(field(panel, "identifier"), "tag").(json.String)
		params, _ := field(field(panel, "globalConfiguration"), "params").(json.String)
		if id == "" || params == "" {return}
		action.kind = .Menu
		request.panel_id, request.params = string(id), string(params)
	} else if browse := field(endpoint, "browseEndpoint"); browse != nil {
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
	if action.kind != .Browse {
		bytes, error := json.marshal(request)
		if error != nil {return {}, false}
		// The action owns the marshalled bytes until its payload is deleted.
		action.payload = string(bytes)
	}
	action.label = strings.clone(label)
	return action, true
}

// Match YouTube.js PlaylistManager.addVideos, using the shared edit endpoint.
watch_later_action :: proc(video_id: string) -> (model.Card_Action, bool) {
	if !video_id_valid(video_id) {return {}, false}
	request := struct {
		ctx:         struct {
			client: Client_Context,
		} `json:"context"`,
		playlist_id: string `json:"playlistId"`,
		actions:     [1]struct {
			action, addedVideoId: string,
		},
	} {
		ctx = {
			client = {clientName = "TVHTML5", clientVersion = TV_VERSION, hl = "en", gl = "US"},
		},
		playlist_id = "WL",
		actions = {{action = "ACTION_ADD_VIDEO", addedVideoId = video_id}},
	}
	bytes, error := json.marshal(request)
	if error != nil {return {}, false}
	return {
			kind = .Edit_Playlist,
			label = strings.clone("Save to Watch later"),
			target = strings.clone("WL"),
			payload = string(bytes),
		},
		true
}

parse_card_actions :: proc(value: json.Value) -> (actions: [dynamic]model.Card_Action) {
	#partial switch item in value {
	case json.Array:
		for child in item {
			actions = parse_card_actions(child)
			if len(actions) > 0 {return}
		}
	case json.Object:
		if item["showEngagementPanelEndpoint"] != nil {
			if action, ok := card_action("More actions", value); ok {append(&actions, action)}
			return
		}
		// Both response formats contain a list of labelled commands.
		items := field(item["menuRenderer"], "items")
		if items == nil {items = field(item["listViewModel"], "listItems")}
		if entries, ok := items.(json.Array); ok {
			for entry in entries {
				label: string
				endpoint: json.Value
				if renderer := field(entry, "listItemViewModel"); renderer != nil {
					disabled, _ := field(renderer, "isDisabled").(json.Boolean)
					if bool(disabled) {continue}
					title, _ := field(field(renderer, "title"), "content").(json.String)
					label = strings.clone(string(title))
					command := field(
						field(field(renderer, "rendererContext"), "commandContext"),
						"onTap",
					)
					endpoint = field(command, "innertubeCommand")
				} else {
					renderer = field(entry, "menuNavigationItemRenderer")
					endpoint = field(renderer, "navigationEndpoint")
					if renderer == nil {
						renderer = field(entry, "menuServiceItemRenderer")
						endpoint = field(renderer, "serviceEndpoint")
					}
					label = text(field(renderer, "text"))
				}
				defer delete(label)
				if label == "Hide" {continue}
				if action, valid := card_action(label, endpoint); valid {append(&actions, action)}
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
	case .Menu:
		route = "get_panel"
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
	#partial switch action.kind {
	case .Menu:
		actions = parse_card_actions(field(value, "content"))
	case .Playlists:
		playlist_actions(value, &actions)
	case:
		return
	}
	if len(actions) == 0 {return nil, .Unavailable}
	return actions, .None
}
