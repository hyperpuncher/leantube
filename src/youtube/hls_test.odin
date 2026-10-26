#+test
package youtube

import "../http"
import "core:strings"
import "core:testing"

@(test)
hls_requires_a_valid_https_manifest_and_does_not_claim_a_resolution :: proc(t: ^testing.T) {
	stream, error := parse_player(
		`{"playabilityStatus":{"status":"OK"},"streamingData":{"hlsManifestUrl":"https://media.example/master.m3u8"}}`,
		true,
	)
	defer delete(stream.url)
	testing.expect_value(t, error, .None)
	testing.expect(t, stream.hls)
	testing.expect_value(t, stream.height, 0)
	testing.expect_value(t, stream.url, "https://media.example/master.m3u8")
	for data in ([]string{`{"playabilityStatus":{"status":"LOGIN_REQUIRED"},"streamingData":{"hlsManifestUrl":"https://media.example/master.m3u8"}}`, `{"playabilityStatus":{"status":"OK"},"streamingData":{"hlsManifestUrl":"http://media.example/master.m3u8"}}`, `{"playabilityStatus":{"status":"OK"},"streamingData":{"serverAbrStreamingUrl":"https://media.example/sabr"}}`}) {
		failed, failure := parse_player(data, true)
		delete(failed.url)
		testing.expect(t, failure != .None)
	}
}

@(test)
hls_uses_the_player_default_audio_language :: proc(t: ^testing.T) {
	for c in ([]struct {
			data:     string,
			language: string,
		}{{`{"playabilityStatus":{"status":"OK"},"streamingData":{"hlsManifestUrl":"https://media.example/master.m3u8","adaptiveFormats":[{"audioTrack":{"id":"ja.3","audioIsDefault":false}},{"audioTrack":{"id":"en.4","audioIsDefault":true}}]}}`, "en"}, {`{"playabilityStatus":{"status":"OK"},"streamingData":{"hlsManifestUrl":"https://media.example/master.m3u8","adaptiveFormats":[{"audioTrack":{"id":"ja.3","audioIsDefault":false}}]}}`, ""}, {`{"playabilityStatus":{"status":"OK"},"streamingData":{"hlsManifestUrl":"https://media.example/master.m3u8"}}`, ""}}) {
		stream, error := parse_player(c.data, true)
		defer delete(stream.url)
		defer delete(stream.audio_language)
		testing.expect_value(t, error, .None)
		testing.expect_value(t, stream.audio_language, c.language)
	}
}

@(test)
hls_uses_the_source_maximum_instead_of_a_fixed_cap :: proc(t: ^testing.T) {
	stream, error := parse_player(
		`{"playabilityStatus":{"status":"OK"},"streamingData":{"hlsManifestUrl":"https://media.example/master.m3u8","adaptiveFormats":[{"width":1280,"height":720,"bitrate":2500000},{"width":3840,"height":1920,"bitrate":53080615},{"width":3840,"height":1920,"bitrate":55873126},{"width":2560,"height":1280,"bitrate":12374073}]}}`,
		true,
	)
	defer delete(stream.url)
	testing.expect_value(t, error, .None)
	testing.expect_value(t, stream.max_width, 3840)
	testing.expect_value(t, stream.max_height, 1920)
	testing.expect_value(t, stream.max_bitrate, 55873126)
}

player_calls: [dynamic]Profile
hls_failure: Error
cancel_player: bool
cancel_after_hls: bool

fake_player :: proc(
	_: ^http.Client,
	id: string,
	profile: Profile,
	visitor: string,
) -> (
	Stream,
	Error,
) {
	assert(id == "C5WDBA2i9nE")
	append(&player_calls, profile)
	if profile == .VisionOS {
		assert(visitor == "test-session")
		if cancel_after_hls {cancel_player = true}
		if hls_failure != .None {return {}, hls_failure}
		return {url = strings.clone("https://media.example/master.m3u8"), hls = true}, .None
	}
	assert(visitor == "")
	return {url = strings.clone("https://media.example/combined.mp4"), height = 360}, .None
}
player_canceled :: proc() -> bool {return cancel_player}

@(test)
resolver_prefers_hls_and_keeps_mp4_when_the_hls_api_is_unavailable :: proc(t: ^testing.T) {
	defer {delete(player_calls); player_calls = nil; hls_failure = .None}
	for failure in ([]Error{.None, .Unavailable, .No_Direct_Stream, .Transport, .HTTP, .Invalid_Response}) {
		clear(&player_calls)
		hls_failure = failure
		stream, error := resolve(nil, "C5WDBA2i9nE", "test-session", request = fake_player)
		defer delete(stream.url)
		testing.expect_value(t, error, .None)
		testing.expect_value(t, stream.hls, failure == .None)
		testing.expect_value(t, player_calls[0], .VisionOS)
		testing.expect_value(t, len(player_calls), failure == .None ? 1 : 2)
		if failure != .None {testing.expect_value(t, player_calls[1], .Android)}
	}
	clear(&player_calls)
	stream, error := resolve(nil, "C5WDBA2i9nE", request = fake_player)
	defer delete(stream.url)
	testing.expect_value(t, error, .None)
	testing.expect(t, !stream.hls)
	testing.expect_value(t, len(player_calls), 1)
	testing.expect_value(t, player_calls[0], .Android)
}

@(test)
canceling_hls_does_not_start_another_player_request :: proc(t: ^testing.T) {
	defer {
		delete(player_calls); player_calls = nil
		cancel_player = false; cancel_after_hls = false; hls_failure = .None
	}
	hls_failure = .Unavailable
	cancel_after_hls = true
	stream, error := resolve(nil, "C5WDBA2i9nE", "test-session", player_canceled, fake_player)
	defer delete(stream.url)
	testing.expect_value(t, error, .Unavailable)
	testing.expect_value(t, len(player_calls), 1)
	clear(&player_calls)
	canceled, canceled_error := resolve(
		nil,
		"C5WDBA2i9nE",
		"test-session",
		player_canceled,
		fake_player,
	)
	delete(canceled.url)
	testing.expect_value(t, canceled_error, .Unavailable)
	testing.expect_value(t, len(player_calls), 0)
}
