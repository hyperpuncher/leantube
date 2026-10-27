#+test
package model

import "core:testing"

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

@(test)
pending_seek_is_displayed_before_the_decoder_reports_it :: proc(t: ^testing.T) {
	seek := Timeline {
		position_ms    = 5_000,
		seek_target_ms = -1,
	}
	testing.expect_value(t, display_position(seek), f64(5_000))
	seek.seek_target_ms = 62_000
	testing.expect_value(t, display_position(seek), f64(62_000))
	seek_done(&seek)
	testing.expect_value(t, display_position(seek), f64(62_000))
}
