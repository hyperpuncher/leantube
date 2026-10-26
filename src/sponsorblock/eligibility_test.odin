#+test
package sponsorblock

import "core:testing"

@(test)
markers_and_skips_share_the_same_eligibility_rules :: proc(t: ^testing.T) {
	for c in ([]struct {
			segment:  Segment,
			eligible: bool,
		}{{{start_ms = 1000, end_ms = 2000}, true}, {{start_ms = 1000, end_ms = 2000, skipped = true}, false}, {{start_ms = -1, end_ms = 2000}, false}, {{start_ms = 2000, end_ms = 1000}, false}, {{start_ms = 1000, end_ms = 10000}, true}, {{start_ms = 1000, end_ms = 10001}, false}, {{start_ms = 1000, end_ms = 2000, video_duration_ms = 11000}, true}, {{start_ms = 1000, end_ms = 2000, video_duration_ms = 11001}, false}}) {
		testing.expect_value(t, can_skip(c.segment, 10000), c.eligible)
		target := skip_target([]Segment{c.segment}, max(c.segment.start_ms, 0), 10000)
		testing.expect_value(t, target >= 0, c.eligible)
	}
	testing.expect(t, !can_skip({start_ms = 1000, end_ms = 2000}, 0))
}
