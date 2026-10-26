package model

Timeline :: struct {
	position_ms:    f64,
	seek_target_ms: f64,
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
