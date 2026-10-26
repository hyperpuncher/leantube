package sponsorblock

import "core:testing"

@(test)
lookup_uses_the_documented_private_hash_prefix :: proc(t: ^testing.T) {
	url := endpoint("dQw4w9WgXcQ")
	defer delete(url)
	testing.expect_value(t, url, "https://sponsor.ajay.app/api/skipSegments/5f6b")
}

@(test)
segments_only_match_the_exact_video_and_supported_action :: proc(t: ^testing.T) {
	segments, valid := parse(
		`[
		{"videoID":"other-video","segments":[{"category":"sponsor","actionType":"skip","segment":[0,99]}]},
		{"videoID":"dQw4w9WgXcQ","segments":[
			{"category":"sponsor","actionType":"skip","segment":[1.25,3.5],"videoDuration":10},
			{"category":"intro","actionType":"skip","segment":[0,1]},
			{"category":"sponsor","actionType":"mute","segment":[4,5]},
			{"category":"sponsor","actionType":"skip","segment":[8,2]},
			{"category":"sponsor","actionType":"skip","segment":[-1,2]}
		]}
	]`,
		"dQw4w9WgXcQ",
	)
	defer delete(segments)
	testing.expect(t, valid)
	if !testing.expect_value(t, len(segments), 1) {return}
	testing.expect_value(t, segments[0].start_ms, f64(1250))
	testing.expect_value(t, segments[0].end_ms, f64(3500))
	testing.expect_value(t, skip_target(segments[:], 1250, 10000), f64(3500))
	testing.expect_value(t, skip_target(segments[:], 1250, 15000), f64(-1))
}

@(test)
overlapping_segments_skip_once_and_never_seek_past_the_video :: proc(t: ^testing.T) {
	segments := [3]Segment {
		{start_ms = 2000, end_ms = 4000},
		{start_ms = 1000, end_ms = 2500},
		{start_ms = 9000, end_ms = 12000},
	}
	testing.expect_value(t, skip_target(segments[:], 0, 10000), f64(-1))
	testing.expect_value(t, skip_target(segments[:], 1000, 10000), f64(4000))
	testing.expect_value(t, skip_target(segments[:], 4000, 10000), f64(-1))
	testing.expect_value(t, skip_target(segments[:], 9000, 10000), f64(-1))
	mark_skipped(segments[:], 1000, 4000)
	testing.expect_value(t, skip_target(segments[:], 1000, 10000), f64(-1))
}
