package main

import "./model"
import sb "./sponsorblock"
import "core:fmt"
import sdl "vendor:sdl3"

// Remote presses move the knob at once. One seek follows the last press, so
// a long jump does not restart the decoder for each step.
SEEK_SETTLE_MS :: 500
seek_pending: struct {
	target_ms: f64,
	at:        u64,
	active:    bool,
}

queue_seek :: proc(offset_ms: f64) {
	shown := timeline
	if seek_pending.active {shown.seek_target_ms = seek_pending.target_ms}
	seek_pending = {model.seek_target(shown, offset_ms, duration_ms), sdl.GetTicks(), true}
}

apply_pending_seek :: proc(now: u64) {
	if seek_pending.active && now - seek_pending.at >= SEEK_SETTLE_MS {
		_ = seek_to(seek_pending.target_ms)
	}
}

shown_position :: proc() -> f64 {
	return seek_pending.active ? seek_pending.target_ms : model.display_position(timeline)
}

seek_to :: proc(target: f64) -> bool {
	seek_pending = {}
	if !player_seek(target) {return false}
	timeline.seek_target_ms = target
	timeline.buffer_start_ms, timeline.buffer_end_ms = 0, 0
	return true
}

auto_skip_sponsor :: proc() {
	if browsing ||
	   !loaded ||
	   paused ||
	   timeline.seek_target_ms >= 0 ||
	   seek_pending.active {return}
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
