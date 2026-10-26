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
	url:    string,
	height: int,
}

// Client profiles follow yt-dlp's YouTube extractor. No account cookies or
// attestation tokens are used. Unsupported playback must fail visibly.
ANDROID_VERSION :: "21.26.364"
ANDROID_AGENT :: "com.google.android.youtube/" + ANDROID_VERSION + " (Linux; U; Android 11) gzip"

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
	if len(catalog.videos) >= model.MAX_VIDEOS {return}
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

parse_search :: proc(data, query: string) -> (catalog: model.Catalog, error: Error) {
	value, err := json.parse(data)
	if err != .None {return {}, .Invalid_Response}
	defer json.destroy_value(value)
	primary := field(
		field(field(value, "contents"), "twoColumnSearchResultsRenderer"),
		"primaryContents",
	)
	if primary == nil {return {}, .Invalid_Response}
	catalog.query = strings.clone(query)
	collect_videos(primary, &catalog)
	return
}

parse_player :: proc(data: string) -> (stream: Stream, error: Error) {
	value, err := json.parse(data)
	if err != .None {return {}, .Invalid_Response}
	defer json.destroy_value(value)
	status, _ := field(field(value, "playabilityStatus"), "status").(json.String)
	if status != "OK" {return {}, .Unavailable}
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
			stream = {strings.clone(string(url)), int(height)}
		}
	}
	if stream.url == "" {return {}, .No_Direct_Stream}
	return
}

Client_Context :: struct {
	clientName, clientVersion, hl, gl: string,
	androidSdkVersion:                 int `json:",omitempty"`,
	userAgent, osName, osVersion:      string `json:",omitempty"`,
}
api_post :: proc(
	client: ^http.Client,
	endpoint: string,
	payload: []u8,
	android: bool = false,
) -> (
	http.Response,
	Error,
) {
	url := fmt.aprintf("https://www.youtube.com/youtubei/v1/%s?prettyPrint=false", endpoint)
	defer delete(url)
	headers := []string{"Content-Type: application/json", "Origin: https://www.youtube.com"}
	if android {headers = {"Content-Type: application/json", "Origin: https://www.youtube.com", "X-YouTube-Client-Name: 3", "X-YouTube-Client-Version: " + ANDROID_VERSION, "User-Agent: " + ANDROID_AGENT}}
	response, err := http.request(
		client,
		url,
		string(payload),
		headers,
		max_bytes = 4 * 1024 * 1024,
		timeout_ms = 3000,
	)
	if err != nil {return {}, .Transport}
	if response.status != 200 {delete(response.body); return {}, .HTTP}
	return response, .None
}
search :: proc(client: ^http.Client, query: string) -> (model.Catalog, Error) {
	if strings.trim_space(query) == "" || len(query) > 512 {return {}, .Invalid_Response}
	request := struct {
		ctx:           struct {
			client: Client_Context,
		} `json:"context"`,
		query, params: string,
	} {
		ctx = {
			client = {
				clientName = "WEB",
				clientVersion = "2.20260708.00.00",
				hl = "en",
				gl = "US",
			},
		},
		query = query,
		params = "EgIQAfABAQ==",
	}
	body, err := json.marshal(request)
	if err != nil {return {}, .Invalid_Response}
	defer delete(body)
	response, error := api_post(client, "search", body)
	if error != .None {return {}, error}
	defer delete(response.body)
	return parse_search(string(response.body[:]), query)
}
resolve :: proc(client: ^http.Client, id: string) -> (Stream, Error) {
	if !video_id_valid(id) {return {}, .Invalid_Response}
	request := struct {
		ctx:     struct {
			client: Client_Context,
		} `json:"context"`,
		videoId: string,
	} {
		ctx = {
			client = {
				clientName = "ANDROID",
				clientVersion = ANDROID_VERSION,
				hl = "en",
				gl = "US",
				androidSdkVersion = 30,
				userAgent = ANDROID_AGENT,
				osName = "Android",
				osVersion = "11",
			},
		},
		videoId = id,
	}
	body, err := json.marshal(request)
	if err != nil {return {}, .Invalid_Response}
	defer delete(body)
	response, error := api_post(client, "player", body, true)
	if error != .None {return {}, error}
	defer delete(response.body)
	return parse_player(string(response.body[:]))
}

fetch_thumbnail :: proc(client: ^http.Client, url: string) -> (http.Response, http.Error) {
	return http.request(client, url, max_bytes = 2 * 1024 * 1024, timeout_ms = 2000)
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
