package youtube

import "../http"
import "core:crypto"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:net"
import "core:strconv"
import "core:strings"

// History needs account-linked metadata, not the anonymous media response.
// The older TV profile uses the web player's five-digit signature timestamp.
// Profile and history protocol checked against SmartTube's MediaServiceCore.
HISTORY_TV_VERSION :: "5.20260901"
HISTORY_TV_AGENT :: "Mozilla/5.0 (DirectFB; Linux x86_64) Cobalt/4.13031-qa (unlike Gecko) Starboard/1"
Watch_History :: struct {
	playback_url, watchtime_url: string,
	cpn:                         [16]u8,
	started:                     bool,
}

watch_history_destroy :: proc(history: ^Watch_History) {
	delete(history.playback_url); delete(history.watchtime_url)
	history^ = {}
}

parse_signature_timestamp :: proc(data: string) -> i64 {
	remaining := data
	for {
		index := strings.index(remaining, "signatureTimestamp")
		if index < 0 {return 0}
		remaining = remaining[index + len("signatureTimestamp"):]
		value := strings.trim_left(remaining, "\"':= \t")
		count := 0
		for count < len(value) && value[count] >= '0' && value[count] <= '9' {count += 1}
		if count > 0 {
			timestamp, ok := strconv.parse_i64(value[:count])
			if ok && timestamp > 0 {return timestamp}
		}
	}
}

fetch_signature_timestamp :: proc(client: ^http.Client) -> i64 {
	response, error := http.request(
		client,
		"https://www.youtube.com/iframe_api",
		timeout_ms = 3000,
	)
	if error != nil {return 0}
	defer delete(response.body)
	if response.status != 200 {return 0}
	page, _ := strings.replace_all(string(response.body[:]), "\\/", "/")
	defer delete(page)
	index := strings.index(page, "/s/player/")
	if index < 0 {return 0}
	tail := page[index + len("/s/player/"):]
	end := strings.index_byte(tail, '/')
	if end <= 0 {return 0}
	id := tail[:end]
	for ch in id {
		if !(ch >= 'a' && ch <= 'z' ||
			   ch >= 'A' && ch <= 'Z' ||
			   ch >= '0' && ch <= '9' ||
			   ch == '_' ||
			   ch == '-') {return 0}
	}
	url := fmt.aprintf("https://www.youtube.com/s/player/%s/player_ias.vflset/en_US/base.js", id)
	defer delete(url)
	script, script_error := http.request(client, url, timeout_ms = 5000)
	if script_error != nil {return 0}
	defer delete(script.body)
	return script.status == 200 ? parse_signature_timestamp(string(script.body[:])) : 0
}

parse_watch_history :: proc(data: string) -> (history: Watch_History, error: Error) {
	value, err := json.parse(data)
	if err != .None {return {}, .Invalid_Response}
	defer json.destroy_value(value)
	tracking := field(value, "playbackTracking")
	for key, i in ([2]string{"videostatsPlaybackUrl", "videostatsWatchtimeUrl"}) {
		link, _ := field(field(tracking, key), "baseUrl").(json.String)
		scheme, host, path, query, fragment := net.split_url(string(link))
		defer delete(query)
		expected := i == 0 ? "/api/stats/playback" : "/api/stats/watchtime"
		if scheme != "https" ||
		   (host != "s.youtube.com" && host != "www.youtube.com") ||
		   path != expected ||
		   fragment != "" {
			watch_history_destroy(&history)
			return {}, .Invalid_Response
		}
		url := net.join_url("https", "www.youtube.com", path, query, "")
		if i == 0 {history.playback_url = url} else {history.watchtime_url = url}
	}
	crypto.rand_bytes(history.cpn[:])
	alphabet := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
	for &byte in history.cpn {byte = alphabet[byte & 63]}
	return
}

fetch_watch_history :: proc(
	client: ^http.Client,
	id, visitor: string,
	timestamp: i64,
) -> (
	Watch_History,
	Error,
) {
	if access_token == "" || !video_id_valid(id) || timestamp <= 0 {return {}, .Unavailable}
	payload := struct {
		ctx:                         struct {
			client: Client_Context,
		} `json:"context"`,
		videoId:                     string,
		contentCheckOk, racyCheckOk: bool,
		playbackContext:             struct {
			contentPlaybackContext:     struct {
				signatureTimestamp: i64,
				html5Preference:    string,
			},
			devicePlaybackCapabilities: struct {
				supportsVp9Encoding, supportXhr: bool,
			},
		},
	} {
		ctx = {
			client = {
				clientName = "TVHTML5",
				clientVersion = HISTORY_TV_VERSION,
				hl = "en",
				gl = "US",
				userAgent = HISTORY_TV_AGENT,
				visitorData = visitor,
			},
		},
		videoId = id,
		contentCheckOk = true,
		racyCheckOk = true,
		playbackContext = {
			contentPlaybackContext = {timestamp, "HTML5_PREF_WANTS"},
			devicePlaybackCapabilities = {true, false},
		},
	}
	body, marshal_error := json.marshal(payload)
	if marshal_error != nil {return {}, .Invalid_Response}
	defer delete(body)
	response, request_error := api_post(client, "player", body, .History)
	if request_error != .None {return {}, request_error}
	defer delete(response.body)
	return parse_watch_history(string(response.body[:]))
}

// Keep credentials in headers, refuse redirects, and never log tracking URLs.
report_watch_history :: proc(
	client: ^http.Client,
	history: ^Watch_History,
	start, position: f64,
	finished: bool = false,
	request: type_of(http.request) = http.request,
) -> Error {
	if access_token == "" ||
	   position < 0 ||
	   start < 0 ||
	   start > position ||
	   math.is_nan(start) ||
	   math.is_inf(start) ||
	   math.is_nan(position) ||
	   math.is_inf(position) {return .Invalid_Response}
	authorization := fmt.aprintf("Authorization: Bearer %s", access_token)
	defer delete(authorization)
	from, to := fmt.aprintf("%.3f", start), fmt.aprintf("%.3f", position)
	defer {delete(from); delete(to)}
	for initial in ([2]bool{true, false}) {
		if initial && history.started {continue}
		base := initial ? history.playback_url : history.watchtime_url
		scheme, host, path, query, fragment := net.split_url(base)
		if query == nil {query = make(map[string]string)}
		defer delete(query)
		if scheme != "https" ||
		   host != "www.youtube.com" ||
		   path != (initial ? "/api/stats/playback" : "/api/stats/watchtime") ||
		   fragment != "" {return .Invalid_Response}
		query["ver"], query["cpn"] = "2", string(history.cpn[:])
		query["cmt"] = initial ? from : to
		if !initial {query["st"], query["et"] = from, to}
		if finished {query["final"] = "1"} else {delete_key(&query, "final")}
		url := net.join_url(scheme, host, path, query, "")
		defer delete(url)
		response, error := request(
			client,
			url,
			headers = {
				authorization,
				"User-Agent: " + HISTORY_TV_AGENT,
				"Referer: https://www.youtube.com/tv",
			},
			timeout_ms = 3000,
		)
		if error != nil {return .Transport}
		delete(response.body)
		if response.status < 200 || response.status >= 300 {return .HTTP}
		if initial {history.started = true}
	}
	return .None
}
