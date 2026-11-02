#+test
package youtube

import "../http"
import "core:c"
import "core:net"
import "core:strings"
import "core:testing"

history_calls: int
history_http_status: c.long = 204
history_test: ^testing.T
history_nonce: string

history_request :: proc(
	_: ^http.Client,
	url: string,
	body: Maybe(string),
	headers: []string,
	_: c.long,
	redirects: bool,
) -> (
	http.Response,
	http.Error,
) {
	t := history_test
	testing.expect(t, body == nil && !redirects)
	testing.expect(t, strings.has_prefix(url, "https://www.youtube.com/api/stats/"))
	found := false
	for header in headers {if header == "Authorization: Bearer history-test-token" {found = true}}
	testing.expect(t, found)
	_, _, path, query, _ := net.split_url(url)
	defer delete(query)
	testing.expect_value(t, query["of"], "opaque%2Bvalue")
	testing.expect_value(t, query["cpn"], history_nonce)
	if history_calls == 0 {
		testing.expect_value(t, path, "/api/stats/playback")
		testing.expect_value(t, query["cmt"], "0.000")
	} else {
		testing.expect_value(t, path, "/api/stats/watchtime")
		testing.expect_value(t, query["st"], history_calls == 1 ? "0.000" : "12.500")
		testing.expect_value(t, query["et"], history_calls == 1 ? "12.500" : "20.000")
		testing.expect_value(t, query["final"], history_calls == 2 ? "1" : "")
	}
	history_calls += 1
	return {status = history_http_status}, nil
}

@(test)
history_keeps_account_tracking_data_and_reuses_one_playback_nonce :: proc(t: ^testing.T) {
	history_test = t
	history_calls = 0
	set_access_token("history-test-token")
	defer {set_access_token(""); history_test = nil; history_nonce = ""; history_calls = 0
		history_http_status = 204}
	history, error := parse_watch_history(
		`{"playbackTracking":{
		"videostatsPlaybackUrl":{"baseUrl":"https://s.youtube.com/api/stats/playback?of=opaque%2Bvalue&vm=fixture"},
		"videostatsWatchtimeUrl":{"baseUrl":"https://s.youtube.com/api/stats/watchtime?of=opaque%2Bvalue&vm=fixture"}}}`,
	)
	if !testing.expect_value(t, error, .None) {return}
	defer watch_history_destroy(&history)
	history_nonce = string(history.cpn[:])
	testing.expect_value(
		t,
		report_watch_history(nil, &history, 0, 12.5, request = history_request),
		.None,
	)
	testing.expect(t, history.started)
	testing.expect_value(t, history_calls, 2)
	testing.expect_value(
		t,
		report_watch_history(nil, &history, 12.5, 20, true, history_request),
		.None,
	)
	testing.expect_value(t, history_calls, 3)
	history.started = false
	history_calls = 0
	history_http_status = 401
	testing.expect_value(
		t,
		report_watch_history(nil, &history, 0, 12.5, request = history_request),
		.HTTP,
	)
	testing.expect(t, !history.started && history_calls == 1)
	set_access_token("")
	testing.expect_value(
		t,
		report_watch_history(nil, &history, 0, 12.5, request = history_request),
		.Invalid_Response,
	)
	testing.expect_value(t, history_calls, 1)
}

@(test)
history_rejects_external_tracking_hosts :: proc(t: ^testing.T) {
	history, error := parse_watch_history(
		`{"playbackTracking":{
		"videostatsPlaybackUrl":{"baseUrl":"https://www.youtube.com/api/stats/playback?of=fixture"},
		"videostatsWatchtimeUrl":{"baseUrl":"https://example.com/api/stats/watchtime?of=fixture"}}}`,
	)
	defer watch_history_destroy(&history)
	testing.expect_value(t, error, .Invalid_Response)
	testing.expect_value(t, history.playback_url, "")
}
