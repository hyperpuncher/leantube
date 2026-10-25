package model

import "core:testing"

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

@(test)
paused_seek_keeps_completed_target :: proc(t: ^testing.T) {
	time := Timeline {
		position_ms    = 2000,
		seek_target_ms = 300000,
	}
	// An old time update can arrive before seekDone.
	time.position_ms = 2100
	seek_done(&time)
	testing.expect_value(t, time.position_ms, f64(300000))
	testing.expect_value(t, time.seek_target_ms, f64(-1))
	// On resume the decoder's actual position replaces the approximate target.
	time.position_ms = 296600
	seek_done(&time)
	testing.expect_value(t, time.position_ms, f64(296600))
}

@(test)
seek_targets_accumulate_and_stay_in_range :: proc(t: ^testing.T) {
	time := Timeline {
		position_ms    = 2000,
		seek_target_ms = -1,
	}
	time.seek_target_ms = seek_target(time, 10000, 60000)
	testing.expect_value(t, seek_target(time, 10000, 60000), f64(22000))
	testing.expect_value(t, seek_target(time, -30000, 60000), f64(0))
	testing.expect_value(t, seek_target(time, 100000, 60000), f64(60000))
	testing.expect_value(t, seek_target(time, 100000, 0), f64(112000))
}
