package youtube

import "../http"
import "../model"
import "core:encoding/json"
import "core:strings"

browse :: proc(
	client: ^http.Client,
	id: string,
	continuation: string = "",
) -> (
	model.Catalog,
	Error,
	string,
) {
	request := struct {
		ctx:          struct {
			client: Client_Context,
		} `json:"context"`,
		browseId:     string `json:",omitempty"`,
		continuation: string `json:",omitempty"`,
	} {
		ctx = {
			client = {
				clientName = "TVHTML5",
				clientVersion = TV_VERSION,
				hl = "en",
				gl = "US",
				userAgent = TV_AGENT,
			},
		},
		browseId = continuation == "" ? id : "",
		continuation = continuation,
	}
	body, err := json.marshal(request)
	if err != nil {return {}, .Invalid_Response, ""}
	defer delete(body)
	response, error := api_post(client, "browse", body, .TV)
	if error != .None {return {}, error, ""}
	defer delete(response.body)
	return parse_browse(string(response.body[:]))
}

parse_browse :: proc(data: string) -> (catalog: model.Catalog, error: Error, visitor: string) {
	value, err := json.parse(data)
	if err != .None {return {}, .Invalid_Response, ""}
	defer json.destroy_value(value)
	contents := field(value, "contents")
	if contents == nil {contents = field(value, "continuationContents")}
	if contents == nil {return {}, .Invalid_Response, ""}
	if text, ok := field(field(value, "responseContext"), "visitorData").(json.String); ok {
		visitor = strings.clone(string(text))
	}
	collect_tiles(contents, &catalog)
	catalog.continuation = browse_continuation(contents)
	return
}

collect_tiles :: proc(value: json.Value, catalog: ^model.Catalog) {
	#partial switch item in value {
	case json.Array:
		for child in item {collect_tiles(child, catalog)}
	case json.Object:
		// Ads and navigation tabs are not feed cards. Only the selected tab's
		// content is a feed; its sibling tabs can contain unrelated channel data.
		if item["adSlotRenderer"] != nil || item["inFeedAdLayoutRenderer"] != nil {return}
		if tab := item["tabRenderer"]; tab != nil {
			selected, _ := field(tab, "selected").(json.Boolean)
			if bool(selected) {collect_tiles(field(tab, "content"), catalog)}
			return
		}
		if tile := item["tileRenderer"]; tile != nil {
			card := parse_tile(tile)
			if card.id == "" && card.browse_id == "" {return}
			for existing in catalog.videos {
				if existing.id == card.id && existing.browse_id == card.browse_id {
					model.video_destroy(&card)
					return
				}
			}
			append(&catalog.videos, card)
			return
		}
		for _, child in item {collect_tiles(child, catalog)}
	}
}

parse_tile :: proc(tile: json.Value) -> (card: model.Video) {
	command := field(tile, "onSelectCommand")
	id, _ := field(field(command, "watchEndpoint"), "videoId").(json.String)
	browse_id, _ := field(field(command, "browseEndpoint"), "browseId").(json.String)
	playlist := strings.has_prefix(string(browse_id), "VL")
	if !playlist && !video_id_valid(string(id)) {return}
	header := field(field(tile, "header"), "tileHeaderRenderer")
	stamp: string
	overlays, _ := field(header, "thumbnailOverlays").(json.Array)
	for overlay in overlays {
		if status := field(overlay, "thumbnailOverlayTimeStatusRenderer"); status != nil {
			stamp = text(field(status, "text"))
			break
		}
	}
	if !playlist && duration(stamp) <= 0 {delete(stamp); return}
	metadata := field(field(tile, "metadata"), "tileMetadataRenderer")
	title := text(field(metadata, "title"))
	if title == "" {delete(stamp); return}
	card = {
		id             = strings.clone(string(id)),
		browse_id      = playlist ? strings.clone(string(browse_id)) : "",
		title          = title,
		duration_label = stamp,
		duration_ms    = playlist ? 0 : duration(stamp),
	}
	lines, _ := field(metadata, "lines").(json.Array)
	if len(lines) > 0 {
		items, _ := field(field(lines[0], "lineRenderer"), "items").(json.Array)
		for item in items {
			label := text(field(field(item, "lineItemRenderer"), "text"))
			if label != "" {card.channel = label; break}
			delete(label)
		}
	}
	thumbnails, _ := field(field(header, "thumbnail"), "thumbnails").(json.Array)
	for thumbnail in thumbnails {
		if url, ok := field(thumbnail, "url").(json.String);
		   ok && strings.has_prefix(string(url), "https://") {
			delete(card.thumbnail_url)
			card.thumbnail_url = strings.clone(string(url))
		}
	}
	return
}

browse_continuation :: proc(value: json.Value) -> string {
	#partial switch item in value {
	case json.Array:
		for child in item {
			if token := browse_continuation(child); token != "" {return token}
		}
	case json.Object:
		if item["adSlotRenderer"] != nil || item["tileRenderer"] != nil {return ""}
		if tab := item["tabRenderer"]; tab != nil {
			selected, _ := field(tab, "selected").(json.Boolean)
			if bool(selected) {return browse_continuation(field(tab, "content"))}
			return ""
		}
		continuations, _ := item["continuations"].(json.Array)
		for entry in continuations {
			if token, ok := field(
				   field(entry, "nextContinuationData"),
				   "continuation",
			   ).(json.String); ok {
				return strings.clone(string(token))
			}
		}
		for _, child in item {
			if token := browse_continuation(child); token != "" {return token}
		}
	}
	return ""
}
