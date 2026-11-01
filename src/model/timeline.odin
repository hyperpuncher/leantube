package model

Timeline :: struct {
	position_ms:                    f64,
	seek_target_ms:                 f64,
	buffer_start_ms, buffer_end_ms: f64,
}

// Both audio and video must be available for a range to be buffered.
set_buffered_range :: proc(time: ^Timeline, start_ms, end_ms, duration_ms: f64) -> bool {
	start := max(0, start_ms)
	end := max(start, end_ms)
	if duration_ms > 0 {start = min(start, duration_ms); end = min(end, duration_ms)}
	if time.buffer_start_ms == start && time.buffer_end_ms == end {return false}
	time.buffer_start_ms, time.buffer_end_ms = start, end
	return true
}

// Show the requested position at once, before the decoder reports it.
display_position :: proc(time: Timeline) -> f64 {
	return time.seek_target_ms >= 0 ? time.seek_target_ms : time.position_ms
}

seek_target :: proc(time: Timeline, offset, duration_ms: f64) -> f64 {
	base := time.seek_target_ms >= 0 ? time.seek_target_ms : time.position_ms
	target := max(0, base + offset)
	return duration_ms > 0 ? min(target, duration_ms) : target
}

seek_done :: proc(time: ^Timeline) {
	// Paused pipelines do not always publish a new currentTime after seeking.
	// Show the requested position until a decoder time update replaces it.
	if time.seek_target_ms >= 0 {
		time.position_ms = time.seek_target_ms
		time.seek_target_ms = -1
	}
}
