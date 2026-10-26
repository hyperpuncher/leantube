#+test
package model

import "core:testing"

@(test)
time_labels_handle_hours_and_unknown_duration :: proc(t: ^testing.T) {
	cases := []struct {
		ms:             f64,
		zero, expected: string,
	}{{0, "00:00", "00:00"}, {0, "--:--", "--:--"}, {3661000, "00:00", "1:01:01"}}
	for c in cases {
		label := time_label(c.ms, c.zero)
		testing.expect_value(t, label, c.expected)
		delete(label)
	}
}

@(test)
grid_navigation_preserves_rows_and_handles_missing_cards :: proc(t: ^testing.T) {
	testing.expect_value(t, grid_move(0, 6, -1, 0), 0)
	testing.expect_value(t, grid_move(2, 6, 1, 0), 2)
	testing.expect_value(t, grid_move(1, 6, 0, 1), 4)
	testing.expect_value(t, grid_move(4, 6, 0, -1), 1)
	testing.expect_value(t, grid_move(2, 5, 0, 1), 4)
	testing.expect_value(t, grid_move(4, 5, 1, 0), 4)
	testing.expect_value(t, grid_move(0, 1, 0, 1), 0)
	testing.expect_value(t, grid_move(0, 0, 1, 0), 0)
	testing.expect_value(t, grid_move(1, 6, 0, 1, 2), 3)
	testing.expect_value(t, grid_move(4, 6, 0, -1, 2), 2)
	testing.expect_value(t, grid_move(1, 6, 0, 1, 1), 2)
}
