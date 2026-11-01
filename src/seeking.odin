package main

import sb "./sponsorblock"
import "core:fmt"

seek_to :: proc(target: f64) -> bool {
	if !player_seek(target) {return false}
	timeline.seek_target_ms = target
	timeline.buffer_start_ms, timeline.buffer_end_ms = 0, 0
	return true
}

auto_skip_sponsor :: proc() {
	if browsing || !loaded || paused || timeline.seek_target_ms >= 0 {return}
	skip_sponsor_at(timeline.position_ms)
}

skip_sponsor_at :: proc(from: f64, minimum_ms: f64 = 0) {
	target := sb.skip_target(sponsor_segments[:], from, duration_ms)
	if target < 0 {return}
	// A coarse presentation callback may already be past a very short section.
	// Do not replay content that was presented after its end.
	target = max(target, minimum_ms)
	target = max(target, sb.skip_target(sponsor_segments[:], target, duration_ms))
	if seek_to(target) {
		fmt.printf("sponsor skip %.3f -> %.3f seconds\n", from / 1000, target / 1000)
		sb.mark_skipped(sponsor_segments[:], from, target)
	}
}
