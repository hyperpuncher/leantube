package youtube

import "../http"
import "../model"
import "core:encoding/json"
import "core:strings"

add_channel_action :: proc(card: ^model.Video, byline: json.Value) {
	endpoint := find_node(byline, "browseEndpoint")
	id, _ := field(endpoint, "browseId").(json.String)
	if !strings.has_prefix(string(id), "UC") {return}
	for action in card.actions {if action.kind == .Browse && action.target == string(id) {return}}
	append(
		&card.actions,
		model.Card_Action {
			kind = .Browse,
			label = strings.clone("Go to channel"),
			target = strings.clone(string(id)),
		},
	)
}

channel_request :: proc(
	client: ^http.Client,
	id, params, continuation, filter, visitor_data: string,
) -> (
	http.Response,
	Error,
) {
	request := struct {
		ctx:                            struct {
			client: Client_Context,
		} `json:"context"`,
		browseId, params, continuation: string `json:",omitempty"`,
	} {
		ctx = {
			client = {
				clientName = "WEB",
				clientVersion = WEB_VERSION,
				hl = "en",
				gl = "US",
				visitorData = visitor_data,
			},
		},
		browseId = id,
		params = params,
		continuation = continuation != "" ? continuation : filter,
	}
	if request.continuation != "" {request.browseId, request.params = "", ""}
	body, err := json.marshal(request)
	if err != nil {return {}, .Invalid_Response}
	defer delete(body)
	return api_post(client, "browse", body)
}

channel_avatar :: proc(client: ^http.Client, id, visitor_data: string) -> string {
	response, error := channel_request(client, id, "", "", "", visitor_data)
	if error != .None {return ""}
	defer delete(response.body)
	value, err := json.parse(string(response.body[:]))
	if err != .None {return ""}
	defer json.destroy_value(value)
	metadata := field(field(value, "metadata"), "channelMetadataRenderer")
	return largest_image(field(field(metadata, "avatar"), "thumbnails"))
}

card_avatar :: proc(value: json.Value) -> string {
	thumbnail := find_node(value, "channelThumbnailWithLinkRenderer")
	if thumbnail != nil {return largest_image(field(field(thumbnail, "thumbnail"), "thumbnails"))}
	avatar := find_node(value, "avatarViewModel")
	return largest_image(field(field(avatar, "image"), "sources"))
}

channel_browse :: proc(
	client: ^http.Client,
	id, params, continuation, filter, visitor_data: string,
) -> (
	model.Catalog,
	Error,
	string,
) {
	response, error := channel_request(client, id, params, continuation, filter, visitor_data)
	if error != .None {return {}, error, ""}
	defer delete(response.body)
	catalog, parse_error, visitor := parse_channel(string(response.body[:]), id)
	// Enter at Videos rather than mixing unrelated shelves from the Home tab.
	if parse_error == .None && params == "" && continuation == "" && filter == "" {
		for tab in catalog.channel.tabs {
			if tab.selected {return catalog, .None, visitor}
		}
		if len(catalog.channel.tabs) > 0 {
			defer model.catalog_destroy(&catalog)
			defer delete(visitor)
			return channel_browse(client, id, catalog.channel.tabs[0].params, "", "", visitor)
		}
	}
	return catalog, parse_error, visitor
}

channel_sorts :: proc(value: json.Value, sorts: ^[dynamic]model.Channel_Option) {
	#partial switch item in value {
	case json.Array:
		for child in item {channel_sorts(child, sorts)}
	case json.Object:
		node := item["listItemViewModel"]
		label, selected, command: json.Value
		if node != nil {
			label = field(field(node, "title"), "content")
			selected = field(node, "isSelected")
			command = field(field(field(node, "rendererContext"), "commandContext"), "onTap")
		} else if node = item["chipViewModel"]; node != nil {
			label = field(node, "text")
			selected = field(node, "selected")
			command = field(node, "tapCommand")
		}
		name, _ := label.(json.String)
		if (name == "Latest" || name == "Popular" || name == "Oldest") &&
		   find_node(command, "showSheetCommand") == nil {
			token, _ := field(find_node(command, "continuationCommand"), "token").(json.String)
			if token != "" {
				label := name == "Latest" ? "Newest" : string(name)
				for option in sorts^ {if option.label == label {return}}
				active, _ := selected.(json.Boolean)
				append(
					sorts,
					model.Channel_Option {
						label = strings.clone(label),
						token = strings.clone(string(token)),
						selected = bool(active),
					},
				)
			}
		}
		for _, child in item {channel_sorts(child, sorts)}
	}
}

parse_channel :: proc(
	data, id: string,
) -> (
	catalog: model.Catalog,
	error: Error,
	visitor: string,
) {
	value, err := json.parse(data)
	if err != .None {return {}, .Invalid_Response, ""}
	defer json.destroy_value(value)
	contents := feed_contents(value)
	if contents == nil {return {}, .Invalid_Response, ""}
	if token, ok := field(field(value, "responseContext"), "visitorData").(json.String);
	   ok {visitor = strings.clone(string(token))}
	catalog.channel.id = strings.clone(id)
	metadata := field(field(value, "metadata"), "channelMetadataRenderer")
	title, _ := field(metadata, "title").(json.String)
	catalog.channel.title = strings.clone(string(title))
	catalog.channel.avatar_url = largest_image(field(field(metadata, "avatar"), "thumbnails"))
	header := field(field(field(value, "header"), "pageHeaderRenderer"), "content")
	header = field(header, "pageHeaderViewModel")
	rows, _ := field(
		field(field(header, "metadata"), "contentMetadataViewModel"),
		"metadataRows",
	).(json.Array)
	parts: [dynamic]string
	defer delete(parts)
	for row in rows {
		items, _ := field(row, "metadataParts").(json.Array)
		for item in items {
			part, _ := field(field(item, "text"), "content").(json.String)
			if part != "" {append(&parts, string(part))}
		}
	}
	catalog.channel.meta = strings.join(parts[:], " · ")
	tabs, _ := field(
		field(field(value, "contents"), "twoColumnBrowseResultsRenderer"),
		"tabs",
	).(json.Array)
	for entry in tabs {
		tab := field(entry, "tabRenderer")
		label, _ := field(tab, "title").(json.String)
		active, _ := field(tab, "selected").(json.Boolean)
		if bool(active) {contents = field(tab, "content")}
		if label != "Videos" && label != "Live" && label != "Playlists" {continue}
		params, _ := field(field(field(tab, "endpoint"), "browseEndpoint"), "params").(json.String)
		if params == "" {continue}
		append(
			&catalog.channel.tabs,
			model.Channel_Option {
				label = strings.clone(string(label)),
				params = strings.clone(string(params)),
				selected = bool(active),
			},
		)
	}
	collect_videos(contents, &catalog)
	collect_lockups(contents, &catalog)
	channel_sorts(find_node(contents, "chipBarViewModel"), &catalog.channel.sorts)
	catalog.continuation = browse_continuation(contents)
	return
}
