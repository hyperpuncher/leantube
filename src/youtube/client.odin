package youtube

import "../http"
import "../model"
import "core:encoding/json"
import "core:fmt"
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
	url:                string,
	height:             int,
	audio_url:          string,
	audio_init_end:     int,
	audio_index_end:    int,
	audio_content_size: int,
	audio_duration_ms:  f64,
	hdr:                Hdr,
}

// Client profiles follow yt-dlp's YouTube extractor. No account cookies or
// attestation tokens are used. Unsupported playback must fail visibly.
ANDROID_VERSION :: "21.26.364"
ANDROID_AGENT :: "com.google.android.youtube/" + ANDROID_VERSION + " (Linux; U; Android 11) gzip"
VISIONOS_VERSION :: "1.02"
VISIONOS_AGENT :: "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
TV_VERSION :: "7.20260707.07.00"
TV_AGENT :: "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)"
Profile :: enum {
	Web,
	TV,
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
			channel := text(video["ownerText"])
			if channel == "" {delete(channel); channel = text(video["longBylineText"])}
			append(
				&catalog.videos,
				model.Video {
					id = strings.clone(string(id)),
					title = title,
					channel = channel,
					duration_label = stamp,
					duration_ms = ms,
				},
			)
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

collect_videos_tv :: proc(value: json.Value, catalog: ^model.Catalog) {
	#partial switch item in value {
	case json.Array:
		for child in item {collect_videos_tv(child, catalog)}
	case json.Object:
		if lockup, ok := item["lockupViewModel"].(json.Object); ok {
			kind, _ := lockup["contentType"].(json.String)
			if kind != "LOCKUP_CONTENT_TYPE_VIDEO" {return}
			id, valid := lockup["contentId"].(json.String)
			if !valid || !video_id_valid(string(id)) {return}
			for existing in catalog.videos {if existing.id == string(id) {return}}
			metadata, _ := lockup["metadata"].(json.Object)
			lockup_metadata, _ := metadata["lockupMetadataViewModel"].(json.Object)
			title, _ := field(lockup_metadata, "title").(json.Object)
			title_text, _ := field(title, "content").(json.String)
			if title_text == "" {return}
			channel: string
			rows, _ := field(
				field(lockup_metadata, "metadata"),
				"contentMetadataViewModel",
			).(json.Object)
			metadata_rows, _ := field(rows, "metadataRows").(json.Array)
			if len(metadata_rows) > 0 {
				row, _ := metadata_rows[0].(json.Object)
				row_parts, _ := field(row, "metadataParts").(json.Array)
				if len(row_parts) > 0 {
					part, _ := row_parts[0].(json.Object)
					channel_text, _ := field(field(part, "text"), "content").(json.String)
					channel = strings.clone(string(channel_text))
				}
			}
			stamp: string
			image, _ := lockup["contentImage"].(json.Object)
			thumbnail, _ := field(image, "thumbnailViewModel").(json.Object)
			overlays, _ := field(thumbnail, "overlays").(json.Array)
			if len(overlays) > 0 {
				overlay, _ := overlays[0].(json.Object)
				bottom, _ := field(overlay, "thumbnailBottomOverlayViewModel").(json.Object)
				badges, _ := field(bottom, "badges").(json.Array)
				if len(badges) > 0 {
					badge, _ := badges[0].(json.Object)
					badge_view, _ := field(badge, "thumbnailBadgeViewModel").(json.Object)
					badge_text, _ := field(badge_view, "text").(json.String)
					stamp = strings.clone(string(badge_text))
				}
			}
			ms := duration(stamp)
			if ms <= 0 {delete(stamp); delete(channel); return}
			append(
				&catalog.videos,
				model.Video {
					id = strings.clone(string(id)),
					title = strings.clone(string(title_text)),
					channel = channel,
					duration_label = stamp,
					duration_ms = ms,
				},
			)
			return
		}
		for _, child in item {collect_videos_tv(child, catalog)}
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
	collect_videos_tv(contents, &catalog)
	return
}

Audio_Format :: struct {
	url:          string,
	init_end:     int,
	index_end:    int,
	content_size: int,
	duration_ms:  f64,
	bitrate:      int,
}

numeric :: proc(value: json.Value) -> (f64, bool) {
	if number, ok := model.number(value); ok {return number, true}
	if text, ok := value.(json.String); ok {
		if number, parsed := strconv.parse_f64(string(text)); parsed {return number, true}
	}
	return 0, false
}

// Prefer the default AAC-LC rendition. When the response has no audioTrack
// metadata, the original rendition is the one without xtags; dubbed tracks
// carry xtags. Its byte ranges let HLS serve the AAC track as a rendition.
original_audio :: proc(formats: json.Array) -> (audio: Audio_Format) {
	for format in formats {
		mime, mime_ok := field(format, "mimeType").(json.String)
		if !mime_ok ||
		   !strings.has_prefix(string(mime), "audio/mp4;") ||
		   !strings.contains(string(mime), "mp4a.40.2") {continue}
		track := field(format, "audioTrack")
		default, marked := field(track, "audioIsDefault").(json.Boolean)
		if marked && !bool(default) {continue}
		if !marked {
			if xtags, dubbed := field(format, "xtags").(json.String); dubbed && len(xtags) > 0 {
				continue
			}
		}
		url, linked := field(format, "url").(json.String)
		init_range := field(format, "initRange")
		index_range := field(format, "indexRange")
		init_end, has_init := numeric(field(init_range, "end"))
		index_end, has_index := numeric(field(index_range, "end"))
		content_size, has_size := numeric(field(format, "contentLength"))
		duration, has_duration := numeric(field(format, "approxDurationMs"))
		bitrate, has_bitrate := numeric(field(format, "bitrate"))
		if !linked || !has_init || !has_index || !has_size || !has_duration || !has_bitrate {
			continue
		}
		if audio.url != "" && int(bitrate) <= audio.bitrate {continue}
		delete(audio.url)
		audio = {
			url          = strings.clone(string(url)),
			init_end     = int(init_end),
			index_end    = int(index_end),
			content_size = int(content_size),
			duration_ms  = duration,
			bitrate      = int(bitrate),
		}
	}
	return
}

parse_player :: proc(data: string, hls: bool = false) -> (stream: Stream, error: Error) {
	value, err := json.parse(data)
	if err != .None {return {}, .Invalid_Response}
	defer json.destroy_value(value)
	status, _ := field(field(value, "playabilityStatus"), "status").(json.String)
	if status != "OK" {return {}, .Unavailable}
	if hls {
		url, _ := field(field(value, "streamingData"), "hlsManifestUrl").(json.String)
		if !strings.has_prefix(string(url), "https://") {return {}, .No_Direct_Stream}
		formats, _ := field(field(value, "streamingData"), "adaptiveFormats").(json.Array)
		audio := original_audio(formats)
		stream = {
			url                = strings.clone(string(url)),
			audio_url          = audio.url,
			audio_init_end     = audio.init_end,
			audio_index_end    = audio.index_end,
			audio_content_size = audio.content_size,
			audio_duration_ms  = audio.duration_ms,
		}
		return stream, .None
	}
	formats, _ := field(field(value, "streamingData"), "formats").(json.Array)
	for format in formats {
		url, ok := field(format, "url").(json.String)
		mime, _ := field(format, "mimeType").(json.String)
		height, _ := model.number(field(format, "height"))
		if !ok ||
		   !strings.has_prefix(string(url), "https://") ||
		   !strings.has_prefix(string(mime), "video/mp4;") ||
		   !strings.contains(string(mime), "avc1") ||
		   !strings.contains(string(mime), "mp4a") {continue}
		if height > f64(stream.height) {
			delete(stream.url)
			stream = {
				url    = strings.clone(string(url)),
				height = int(height),
			}
		}
	}
	if stream.url == "" {return {}, .No_Direct_Stream}
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
	case .TV:
		headers = {
			"Content-Type: application/json",
			"Origin: https://www.youtube.com",
			"X-YouTube-Client-Name: 7",
			"X-YouTube-Client-Version: " + TV_VERSION,
			"User-Agent: " + TV_AGENT,
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
	if access_token != "" && profile == .TV {
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
			if photo, has_photo := item["accountPhoto"].(json.Object); has_photo {
				if thumbnails, has_thumbs := photo["thumbnails"].(json.Array); has_thumbs {
					for thumbnail in thumbnails {
						if url, has_url := field(thumbnail, "url").(json.String); has_url {
							delete(avatar_url^)
							avatar_url^ = strings.clone(string(url))
						}
					}
				}
			}
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
		clientVersion = "2.20260708.00.00",
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
			clientVersion = "2.20260708.00.00",
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
) -> (
	Stream,
	Error,
) {
	if !video_id_valid(id) {return {}, .Invalid_Response}
	if stop_when != nil && stop_when() {return {}, .Unavailable}
	if visitor_data != "" {
		stream, error := request(client, id, .VisionOS, visitor_data)
		if error == .None {return stream, error}
		if stop_when != nil && stop_when() {return {}, .Unavailable}
	}
	return request(client, id, .Android, "")
}

player_request :: proc(
	client: ^http.Client,
	id: string,
	profile: Profile,
	visitor_data: string = "",
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
	stream, parse_error := parse_player(string(response.body[:]), profile == .VisionOS)
	if parse_error == .None && profile == .VisionOS {_ = localize_hls(client, &stream)}
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
