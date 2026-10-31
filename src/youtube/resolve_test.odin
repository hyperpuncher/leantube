#+test
package youtube

import "../http"
import "core:strings"
import "core:testing"

player_calls: [dynamic]Profile
profile_failure: Error
cancel_player: bool
cancel_after_profile: bool

fake_player :: proc(
	_: ^http.Client,
	id: string,
	profile: Profile,
	visitor: string,
	_: []Video_Limit,
) -> (
	Stream,
	Error,
) {
	assert(id == "C5WDBA2i9nE")
	append(&player_calls, profile)
	if profile == .VisionOS {
		assert(visitor == "test-session")
		if cancel_after_profile {cancel_player = true}
		if profile_failure != .None {return {}, profile_failure}
		return {url = strings.clone("https://media.example/video.webm")}, .None
	}
	assert(visitor == "")
	return {url = strings.clone("https://media.example/video.mp4"), height = 360}, .None
}
player_canceled :: proc() -> bool {return cancel_player}

@(test)
resolver_tries_the_alternate_profile_when_direct_sources_are_unavailable :: proc(t: ^testing.T) {
	defer {delete(player_calls); player_calls = nil; profile_failure = .None}
	for failure in ([]Error{.None, .Unavailable, .No_Direct_Stream, .Transport, .HTTP, .Invalid_Response}) {
		clear(&player_calls)
		profile_failure = failure
		stream, error := resolve(nil, "C5WDBA2i9nE", "test-session", request = fake_player)
		defer delete(stream.url)
		testing.expect_value(t, error, .None)
		testing.expect_value(t, strings.has_suffix(stream.url, "video.webm"), failure == .None)
		testing.expect_value(t, player_calls[0], .VisionOS)
		testing.expect_value(t, len(player_calls), failure == .None ? 1 : 2)
		if failure != .None {testing.expect_value(t, player_calls[1], .Android)}
	}
	clear(&player_calls)
	stream, error := resolve(nil, "C5WDBA2i9nE", request = fake_player)
	defer delete(stream.url)
	testing.expect_value(t, error, .None)
	testing.expect(t, strings.has_suffix(stream.url, "video.mp4"))
	testing.expect_value(t, len(player_calls), 1)
	testing.expect_value(t, player_calls[0], .Android)
}

@(test)
canceling_resolution_does_not_start_another_player_request :: proc(t: ^testing.T) {
	defer {
		delete(player_calls); player_calls = nil
		cancel_player = false; cancel_after_profile = false; profile_failure = .None
	}
	profile_failure = .Unavailable
	cancel_after_profile = true
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
