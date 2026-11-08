package youtube

import "../http"
import "../model"
import "core:encoding/base64"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:net"
import "core:strconv"
import "core:strings"

Error :: enum {
	None,
	Transport,
	HTTP,
	Invalid_Response,
	Unavailable,
	No_Direct_Stream,
}
Stream :: struct {
	url:         string,
	width:       int,
	height:      int,
	audio_url:   string,
	channel_id:  string,
	title:       string,
	duration_ms: f64,
	// Playback client that produced the URLs, for diagnostics only.
	client:      string,
}

stream_destroy :: proc(stream: ^Stream) {
	delete(stream.url); delete(stream.audio_url)
	delete(stream.channel_id); delete(stream.title)
	stream^ = {}
}

// Client profiles follow yt-dlp's YouTube extractor. No account cookies or
// attestation tokens are used. Unsupported playback must fail visibly.
WEB_VERSION :: "2.20260708.00.00"
ANDROID_VERSION :: "21.26.364"
ANDROID_AGENT :: "com.google.android.youtube/" + ANDROID_VERSION + " (Linux; U; Android 11) gzip"
VISIONOS_VERSION :: "1.02"
VISIONOS_AGENT :: "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
TV_VERSION :: "7.20260707.07.00"
TV_AGENT :: "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)"
Profile :: enum {
	Web,
	TV,
	History,
	Android,
	VisionOS,
}

access_token: string

set_access_token :: proc(token: string) {
	if token == access_token {return}
	delete(access_token)
	access_token = strings.clone(token)
}

field :: proc(value: json.Value, name: string) -> json.Value {
	object, ok := value.(json.Object)
	if !ok {return nil}
	return object[name]
}
// Borrow a renderer or command from the response. The JSON value owns it.
find_node :: proc(value: json.Value, key: string) -> json.Value {
	#partial switch item in value {
	case json.Object:
		if node := item[key]; node != nil {return node}
		for _, child in item {if node := find_node(child, key); node != nil {return node}}
	case json.Array:
		for child in item {if node := find_node(child, key); node != nil {return node}}
	}
	return nil
}

largest_image :: proc(images: json.Value) -> (url: string) {
	items, _ := images.(json.Array)
	best: f64 = -1
	for item in items {
		link, _ := field(item, "url").(json.String)
		width, _ := numeric(field(item, "width"))
		if !strings.has_prefix(string(link), "https://") || width <= best {continue}
		delete(url)
		url = strings.clone(string(link))
		best = width
	}
	return
}

text :: proc(value: json.Value) -> string {
	if simple, ok := field(value, "simpleText").(json.String);
	   ok {return strings.clone(string(simple))}
	runs, _ := field(value, "runs").(json.Array)
	parts := make([dynamic]string)
	defer delete(parts)
	for run in runs {
		if part, ok := field(run, "text").(json.String); ok {append(&parts, string(part))}
	}
	return strings.concatenate(parts[:])
}
// fill_card_labels reads the channel, view count and relative date from the
// flat labels YouTube serves on a card, in any order. The labels stay owned by
// the caller.
fill_card_labels :: proc(card: ^model.Video, labels: []string) {
	card.published_age_s = -1
	views: u64
	relative: string
	defer delete(relative)
	for label in labels {
		switch {
		case strings.contains(label, "views"):
			views = model.views_count(label)
		case relative == "" && strings.has_suffix(label, "ago"):
			relative = strings.clone(label)
			if age, ok := model.relative_age(label); ok {card.published_age_s = age}
		case card.channel == "" && label != "•":
			card.channel = strings.clone(label)
		}
	}
	delete(card.meta)
	card.meta = model.video_meta(views, relative)
}

// Read both thumbnail overlay formats. Missing progress means unwatched.
watched_percent :: proc(overlays: json.Value) -> f32 {
	resume := find_node(overlays, "thumbnailOverlayResumePlaybackRenderer")
	percent, ok := numeric(field(resume, "percentDurationWatched"))
	if !ok {
		bar := find_node(overlays, "thumbnailOverlayProgressBarViewModel")
		percent, _ = numeric(field(bar, "startPercent"))
	}
	return f32(clamp(percent, 0, 100))
}

// Briefly opened videos report a small percentage, so treat those as unwatched.
MIN_RESUME_PERCENT :: 10

// Prefer the exact playback timestamp; other cards only carry a rounded percent.
resume_start :: proc(exact_ms: f64, exact_known: bool, duration_ms: f64, percent: f32) -> f64 {
	if percent >= 100 {return 0}
	if exact_known {return exact_ms}
	if duration_ms <= 0 || percent <= MIN_RESUME_PERCENT {return 0}
	return duration_ms * f64(percent) / 100
}

// Read only the card's playback action, not timestamps in menus or other videos.
// YouTube.js WatchEndpoint exposes startTimeSeconds; overlays only expose percent.
read_resume_position :: proc(card: ^model.Video, command: json.Value) {
	exact_ms: f64
	known: bool
	endpoint := find_node(command, "watchEndpoint")
	id, _ := field(endpoint, "videoId").(json.String)
	if string(id) == card.id {
		seconds, ok := numeric(field(endpoint, "startTimeSeconds"))
		valid :=
			ok &&
			!math.is_nan(seconds) &&
			!math.is_inf(seconds) &&
			seconds >= 0 &&
			(card.duration_ms <= 0 || seconds <= card.duration_ms / 1000)
		if valid {
			exact_ms, known = seconds * 1000, true
		}
	}
	card.resume_ms = resume_start(exact_ms, known, card.duration_ms, card.watched_percent)
}

video_id_valid :: proc(id: string) -> bool {
	if len(id) != 11 {return false}
	for ch in id {
		if !(ch >= 'a' && ch <= 'z' ||
			   ch >= 'A' && ch <= 'Z' ||
			   ch >= '0' && ch <= '9' ||
			   ch == '-' ||
			   ch == '_') {return false}
	}
	return true
}

duration :: proc(label: string) -> f64 {
	parts := strings.split(label, ":")
	defer delete(parts)
	if len(parts) < 2 || len(parts) > 3 {return 0}
	seconds: i64
	for part in parts {
		n, ok := strconv.parse_i64(part)
		if !ok || n < 0 {return 0}
		seconds = seconds * 60 + n
	}
	return f64(seconds) * 1000
}

collect_videos :: proc(value: json.Value, catalog: ^model.Catalog) {
	#partial switch item in value {
	case json.Array:
		for child in item {collect_videos(child, catalog)}
	case json.Object:
		if video, ok := item["videoRenderer"].(json.Object); ok {
			id, valid := video["videoId"].(json.String)
			if !valid || !video_id_valid(string(id)) {return}
			for existing in catalog.videos {if existing.id == string(id) {return}}
			stamp := text(video["lengthText"])
			ms := duration(stamp)
			if ms <= 0 {delete(stamp); return} 	// Live and upcoming entries are not playable here.
			title := text(video["title"])
			if title == "" {delete(title); delete(stamp); return}
			card := model.Video {
				id              = strings.clone(string(id)),
				watched_percent = watched_percent(video["thumbnailOverlays"]),
				watch_later     = watch_later_state(video["thumbnailOverlays"]),
				title           = title,
				duration_label  = stamp,
				duration_ms     = ms,
			}
			read_resume_position(&card, video["navigationEndpoint"])
			view_text := text(video["viewCountText"])
			published := text(video["publishedTimeText"])
			defer delete(view_text)
			defer delete(published)
			fill_card_labels(&card, []string{view_text, published})
			card.actions = parse_card_actions(video["menu"])
			card.thumbnail_url = largest_image(field(video["thumbnail"], "thumbnails"))
			card.avatar_url = card_avatar(video["channelThumbnailSupportedRenderers"])
			if card.channel == "" {
				card.channel = text(video["ownerText"])
				if card.channel == "" {card.channel = text(video["longBylineText"])}
			}
			byline := video["ownerText"]
			if byline == nil {byline = video["longBylineText"]}
			add_channel_action(&card, byline)
			append(&catalog.videos, card)
			return
		}
		for _, child in item {collect_videos(child, catalog)}
	}
}

// The caller owns visitor_data. Keep it on the network worker, not in UI metadata.
parse_search :: proc(
	data, query: string,
) -> (
	catalog: model.Catalog,
	error: Error,
	visitor_data: string,
) {
	value, err := json.parse(data)
	if err != .None {return {}, .Invalid_Response, ""}
	defer json.destroy_value(value)
	primary := field(
		field(field(value, "contents"), "twoColumnSearchResultsRenderer"),
		"primaryContents",
	)
	if primary == nil {return {}, .Invalid_Response, ""}
	if visitor, ok := field(field(value, "responseContext"), "visitorData").(json.String); ok {
		visitor_data = strings.clone(string(visitor))
	}
	catalog.query = strings.clone(query)
	collect_videos(primary, &catalog)
	return
}

collect_lockups :: proc(value: json.Value, catalog: ^model.Catalog) {
	#partial switch item in value {
	case json.Array:
		for child in item {collect_lockups(child, catalog)}
	case json.Object:
		if lockup, ok := item["lockupViewModel"].(json.Object); ok {
			kind, _ := lockup["contentType"].(json.String)
			playlist := kind == "LOCKUP_CONTENT_TYPE_PLAYLIST"
			if kind != "LOCKUP_CONTENT_TYPE_VIDEO" && !playlist {return}
			id, valid := lockup["contentId"].(json.String)
			if !valid || id == "" || (!playlist && !video_id_valid(string(id))) {return}
			for existing in catalog.videos {
				if (!playlist && existing.id == string(id)) ||
				   (playlist &&
						   strings.trim_prefix(existing.browse_id, "VL") == string(id)) {return}
			}
			metadata, _ := lockup["metadata"].(json.Object)
			lockup_metadata, _ := metadata["lockupMetadataViewModel"].(json.Object)
			title, _ := field(lockup_metadata, "title").(json.Object)
			title_text, _ := field(title, "content").(json.String)
			if title_text == "" {return}
			labels: [dynamic]string
			defer {
				for label in labels {delete(label)}
				delete(labels)
			}
			rows, _ := field(
				field(lockup_metadata, "metadata"),
				"contentMetadataViewModel",
			).(json.Object)
			metadata_rows, _ := field(rows, "metadataRows").(json.Array)
			for row in metadata_rows {
				row_parts, _ := field(row, "metadataParts").(json.Array)
				for part in row_parts {
					label, _ := field(field(part, "text"), "content").(json.String)
					if label != "" {append(&labels, strings.clone(string(label)))}
				}
			}
			stamp: string
			image, _ := lockup["contentImage"].(json.Object)
			thumbnail := find_node(image, "thumbnailViewModel")
			overlays, _ := field(thumbnail, "overlays").(json.Array)
			for overlay in overlays {
				bottom := field(overlay, "thumbnailBottomOverlayViewModel")
				if bottom == nil {bottom = field(overlay, "thumbnailOverlayBadgeViewModel")}
				badges, _ := field(bottom, "badges").(json.Array)
				for badge in badges {
					badge_text, _ := field(
						field(badge, "thumbnailBadgeViewModel"),
						"text",
					).(json.String)
					if badge_text != "" && (playlist || duration(string(badge_text)) > 0) {
						stamp = strings.clone(string(badge_text))
						break
					}
				}
				if stamp != "" {break}
			}
			ms := duration(stamp)
			if !playlist && ms <= 0 {delete(stamp); return}
			card := model.Video {
				watched_percent = playlist ? 0 : watched_percent(field(thumbnail, "overlays")),
				watch_later     = watch_later_state(field(thumbnail, "overlays")),
				id              = playlist ? "" : strings.clone(string(id)),
				browse_id       = playlist ? fmt.aprintf("VL%s", string(id)) : "",
				title           = strings.clone(string(title_text)),
				duration_label  = stamp,
				duration_ms     = ms,
			}
			if !playlist {
				read_resume_position(
					&card,
					field(field(lockup["rendererContext"], "commandContext"), "onTap"),
				)
			}
			fill_card_labels(&card, labels[:])
			card.actions = parse_card_actions(lockup)
			card.thumbnail_url = largest_image(field(field(thumbnail, "image"), "sources"))
			card.avatar_url = card_avatar(field(lockup_metadata, "image"))
			add_channel_action(&card, field(lockup_metadata, "metadata"))
			append(&catalog.videos, card)
			return
		}
		for _, child in item {collect_lockups(child, catalog)}
	}
}

parse_search_tv :: proc(
	data, query: string,
) -> (
	catalog: model.Catalog,
	error: Error,
	visitor_data: string,
) {
	value, err := json.parse(data)
	if err != .None {return {}, .Invalid_Response, ""}
	defer json.destroy_value(value)
	contents := field(value, "contents")
	if field(contents, "sectionListRenderer") == nil {
		return {}, .Invalid_Response, ""
	}
	if visitor, ok := field(field(value, "responseContext"), "visitorData").(json.String); ok {
		visitor_data = strings.clone(string(visitor))
	}
	catalog.query = strings.clone(query)
	collect_lockups(contents, &catalog)
	return
}

Audio_Format :: struct {
	url:     string,
	bitrate: int,
}

numeric :: proc(value: json.Value) -> (f64, bool) {
	if number, ok := model.number(value); ok {return number, true}
	if text, ok := value.(json.String); ok {
		if number, parsed := strconv.parse_f64(string(text)); parsed {return number, true}
	}
	return 0, false
}

// Prefer the default AAC-LC rendition. When the response has no audioTrack
// metadata, accept a rendition unless its content tags mark a dub or DRC. Signed source URLs are not logged or written to disk.
original_audio :: proc(formats: json.Array) -> (audio: Audio_Format) {
	for format in formats {
		mime, mime_ok := field(format, "mimeType").(json.String)
		if !mime_ok ||
		   !strings.has_prefix(string(mime), "audio/mp4;") ||
		   !strings.contains(string(mime), "mp4a.40.2") {continue}
		original := false
		if tags, tagged := field(format, "xtags").(json.String); tagged && tags != "" {
			encoded, valid := net.percent_decode(string(tags))
			if !valid {continue}
			decoded, err := base64.decode(encoded, base64.DEC_URL_TABLE)
			delete(encoded)
			if err != nil {continue}
			// Canonical FormatXTags key/value pairs. Keep explicit original
			// audio even when a translated track is the account default.
			data := string(decoded)
			original = strings.contains(data, "\x0a\x05acont\x12\x08original")
			other := strings.contains(data, "\x0a\x05acont") && !original
			drc := strings.contains(data, "\x0a\x03drc\x12\x011")
			delete(decoded)
			if other || drc {continue}
		}
		default, marked := field(field(format, "audioTrack"), "audioIsDefault").(json.Boolean)
		if !original && marked && !bool(default) {continue}
		url, linked := field(format, "url").(json.String)
		bitrate, has_bitrate := numeric(field(format, "bitrate"))
		drc, _ := field(format, "isDrc").(json.Boolean)
		if !linked ||
		   !strings.has_prefix(string(url), "https://") ||
		   !has_bitrate ||
		   bool(drc) {continue}
		if audio.url != "" && int(bitrate) <= audio.bitrate {continue}
		delete(audio.url)
		audio = {
			url     = strings.clone(string(url)),
			bitrate = int(bitrate),
		}
	}
	return
}

Client_Context :: struct {
	clientName, clientVersion, hl, gl:              string,
	androidSdkVersion:                              int `json:",omitempty"`,
	userAgent, osName, osVersion:                   string `json:",omitempty"`,
	deviceMake, deviceModel, visitorData, timeZone: string `json:",omitempty"`,
	utcOffsetMinutes:                               int,
}
api_post :: proc(
	client: ^http.Client,
	endpoint: string,
	payload: []u8,
	profile: Profile = .Web,
	request: type_of(http.request) = http.request,
) -> (
	http.Response,
	Error,
) {
	url := fmt.aprintf("https://www.youtube.com/youtubei/v1/%s?prettyPrint=false", endpoint)
	defer delete(url)
	headers: []string = {"Content-Type: application/json", "Origin: https://www.youtube.com"}
	#partial switch profile {
	case .TV, .History:
		headers = {
			"Content-Type: application/json",
			"Origin: https://www.youtube.com",
			"X-YouTube-Client-Name: 7",
			profile == .History ? "X-YouTube-Client-Version: " + HISTORY_TV_VERSION : "X-YouTube-Client-Version: " + TV_VERSION,
			profile == .History ? "User-Agent: " + HISTORY_TV_AGENT : "User-Agent: " + TV_AGENT,
		}
	case .Android:
		headers = {
			"Content-Type: application/json",
			"Origin: https://www.youtube.com",
			"X-YouTube-Client-Name: 3",
			"X-YouTube-Client-Version: " + ANDROID_VERSION,
			"User-Agent: " + ANDROID_AGENT,
		}
	case .VisionOS:
		headers = {
			"Content-Type: application/json",
			"Origin: https://www.youtube.com",
			"X-YouTube-Client-Name: 101",
			"X-YouTube-Client-Version: " + VISIONOS_VERSION,
			"User-Agent: " + VISIONOS_AGENT,
		}
	}
	request_headers: [dynamic]string
	defer delete(request_headers)
	for header in headers {append(&request_headers, header)}
	// Odin defers run at block exit. Keep this string until the request returns.
	authorization: string
	defer delete(authorization)
	if access_token != "" && (profile == .TV || profile == .History) {
		authorization = fmt.aprintf("Authorization: Bearer %s", access_token)
		append(&request_headers, authorization)
	}
	response, err := request(client, url, string(payload), request_headers[:], timeout_ms = 3000)
	if err != nil {return {}, .Transport}
	if response.status != 200 {delete(response.body); return {}, .HTTP}
	return response, .None
}
account_info :: proc(client: ^http.Client) -> (name, avatar_url: string) {
	body :=
		`{"context":{"client":{"clientName":"TVHTML5","clientVersion":"` +
		TV_VERSION +
		`","hl":"en","gl":"US"}}}`
	response, error := api_post(client, "account/accounts_list", transmute([]u8)body, .TV)
	if error != .None {return}
	defer delete(response.body)
	value, parse_error := json.parse(string(response.body[:]))
	if parse_error != .None {return}
	defer json.destroy_value(value)
	find_account(value, &name, &avatar_url)
	return
}

find_account :: proc(value: json.Value, name, avatar_url: ^string) {
	#partial switch item in value {
	case json.Array:
		for child in item {
			find_account(child, name, avatar_url)
			if name^ != "" {return}
		}
	case json.Object:
		if account, is_account := item["accountName"].(json.Object); is_account {
			if text, has_text := account["simpleText"].(json.String); has_text {
				name^ = strings.clone(string(text))
			}
			delete(avatar_url^)
			avatar_url^ = largest_image(field(item["accountPhoto"], "thumbnails"))
			return
		}
		for _, child in item {if name^ != "" {return}; find_account(child, name, avatar_url)}
	}
}

search :: proc(client: ^http.Client, query: string) -> (model.Catalog, Error, string) {
	if strings.trim_space(query) == "" || len(query) > 512 {return {}, .Invalid_Response, ""}
	tv := access_token != ""
	client_context := Client_Context {
		clientName    = "WEB",
		clientVersion = WEB_VERSION,
		hl            = "en",
		gl            = "US",
	}
	if tv {
		client_context = {
			clientName    = "TVHTML5",
			clientVersion = TV_VERSION,
			hl            = "en",
			gl            = "US",
			userAgent     = TV_AGENT,
		}
	}
	request := struct {
		ctx:           struct {
			client: Client_Context,
		} `json:"context"`,
		query, params: string,
	} {
		ctx = {client = client_context},
		query = query,
		params = "EgIQAfABAQ==",
	}
	body, err := json.marshal(request)
	if err != nil {return {}, .Invalid_Response, ""}
	if tv {
		response, request_error := api_post(client, "search", body, .TV)
		if request_error == .None {
			catalog, parse_error, visitor := parse_search_tv(string(response.body[:]), query)
			delete(response.body)
			if parse_error == .None {delete(body); return catalog, .None, visitor}
			model.catalog_destroy(&catalog)
			delete(visitor)
		}
		request.ctx.client = Client_Context {
			clientName    = "WEB",
			clientVersion = WEB_VERSION,
			hl            = "en",
			gl            = "US",
		}
		delete(body)
		body, err = json.marshal(request)
		if err != nil {return {}, .Invalid_Response, ""}
	}
	defer delete(body)
	response, error := api_post(client, "search", body)
	if error != .None {return {}, error, ""}
	defer delete(response.body)
	return parse_search(string(response.body[:]), query)
}
Player_Request :: #type proc(
	client: ^http.Client,
	id: string,
	profile: Profile,
	visitor_data: string,
	limits: []Video_Limit,
) -> (
	Stream,
	Error,
)

resolve :: proc(
	client: ^http.Client,
	id: string,
	visitor_data: string = "",
	stop_when: proc() -> bool = nil,
	request: Player_Request = player_request,
	limits: []Video_Limit = nil,
) -> (
	Stream,
	Error,
) {
	if !video_id_valid(id) {return {}, .Invalid_Response}
	if stop_when != nil && stop_when() {return {}, .Unavailable}
	if visitor_data != "" {
		stream, error := request(client, id, .VisionOS, visitor_data, limits)
		if error == .None {return stream, error}
		if stop_when != nil && stop_when() {return {}, .Unavailable}
	}
	return request(client, id, .Android, "", limits)
}

player_request :: proc(
	client: ^http.Client,
	id: string,
	profile: Profile,
	visitor_data: string = "",
	limits: []Video_Limit = nil,
) -> (
	Stream,
	Error,
) {
	profile_context := Client_Context {
		clientName        = "ANDROID",
		clientVersion     = ANDROID_VERSION,
		hl                = "en",
		gl                = "US",
		androidSdkVersion = 30,
		userAgent         = ANDROID_AGENT,
		osName            = "Android",
		osVersion         = "11",
	}
	if profile == .VisionOS {
		profile_context = {
			clientName    = "VISIONOS",
			clientVersion = VISIONOS_VERSION,
			hl            = "en",
			gl            = "US",
			deviceMake    = "Apple",
			deviceModel   = "RealityDevice17,1",
			userAgent     = VISIONOS_AGENT,
			osName        = "visionOS",
			osVersion     = "26.5.23O471",
			timeZone      = "UTC",
			visitorData   = visitor_data,
		}
	}
	request := struct {
		ctx:                         struct {
			client: Client_Context,
		} `json:"context"`,
		videoId:                     string,
		contentCheckOk, racyCheckOk: bool,
	} {
		ctx = {client = profile_context},
		videoId = id,
		contentCheckOk = true,
		racyCheckOk = true,
	}
	body, err := json.marshal(request)
	if err != nil {return {}, .Invalid_Response}
	defer delete(body)
	response, error := api_post(client, "player", body, profile)
	if error != .None {return {}, error}
	defer delete(response.body)
	stream, parse_error := parse_player(string(response.body[:]), limits)
	if parse_error == .None {
		stream.client = profile == .VisionOS ? "visionos" : "android"
	}
	return stream, parse_error
}

fetch_thumbnail :: proc(client: ^http.Client, url: string) -> (http.Response, http.Error) {
	return http.request(client, url, timeout_ms = 2000)
}

thumbnail :: proc(
	client: ^http.Client,
	id: string,
	stop_when: proc() -> bool = nil,
	fetch: proc(
		client: ^http.Client,
		url: string,
	) -> (
		http.Response,
		http.Error,
	) = fetch_thumbnail,
) -> (
	bytes: [dynamic]u8,
) {
	if !video_id_valid(id) {return nil}
	for size in ([]string{"maxresdefault", "hq720", "sddefault", "hqdefault"}) {
		for extension in ([]string{"webp", "jpg"}) {
			if stop_when != nil && stop_when() {return nil}
			path := extension == "webp" ? "vi_webp" : "vi"
			url := fmt.aprintf("https://i.ytimg.com/%s/%s/%s.%s", path, id, size, extension)
			response, err := fetch(client, url)
			delete(url)
			if err != nil {return nil}
			if response.status == 200 {return response.body}
			delete(response.body)
			if response.status != 404 {return nil}
		}
	}
	return nil
}
