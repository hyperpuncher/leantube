package model

import "core:fmt"
import "core:strings"
import "core:testing"

GRID_COLUMNS :: 3
MAX_VIDEOS :: 24
Video :: struct {
	duration_ms:                        f64,
	id, title, channel, duration_label: string,
}
Catalog :: struct {
	query:  string,
	videos: [dynamic]Video,
}

time_label :: proc(ms: f64, zero: string = "00:00") -> string {
	if ms <= 0 {return strings.clone(zero)}
	seconds := i64(ms / 1000)
	if seconds >=
	   3600 {return fmt.aprintf("%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)}
	return fmt.aprintf("%02d:%02d", seconds / 60, seconds % 60)
}

catalog_destroy :: proc(catalog: ^Catalog) {
	for video in catalog.videos {
		delete(video.id); delete(video.title); delete(video.channel); delete(video.duration_label)
	}
	delete(catalog.videos)
	delete(catalog.query)
	catalog^ = {}
}

// Stay in the current row at horizontal edges. Down selects the last card
// when the final row is incomplete. Selection never wraps or leaves the grid.
grid_move :: proc(selected, count, dx, dy: int, columns: int = GRID_COLUMNS) -> int {
	if count <= 0 {return 0}
	current := clamp(selected, 0, count - 1)
	row := current / columns
	column := clamp(current % columns + dx, 0, columns - 1)
	if dy != 0 {row = clamp(row + dy, 0, (count - 1) / columns)}
	return min(row * columns + column, count - 1)
}

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
