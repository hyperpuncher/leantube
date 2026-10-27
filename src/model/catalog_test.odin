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
quality_labels_use_the_standard_tier_not_the_raw_frame_size :: proc(t: ^testing.T) {
	for c in ([]struct {
			width, height: int,
			label:         string,
		}{{1920, 804, "1080p"}, {2048, 858, "1080p"}, {3840, 1600, "2160p"}, {1280, 720, "720p"}, {854, 480, "480p"}, {1440, 1080, "1080p"}, {2560, 1080, "1080p"}, {1080, 1920, "1080p"}, {0, 0, ""}}) {
		testing.expect_value(t, quality_label(c.width, c.height), c.label)
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

@(test)
view_counts_round_to_one_compact_caption :: proc(t: ^testing.T) {
	for c in ([]struct {
			views: u64,
			label: string,
		}{{0, ""}, {7, "7 views"}, {987, "987 views"}, {1_000, "1.0K views"}, {1_234, "1.2K views"}, {12_345, "12K views"}, {179_000, "179K views"}, {999_499, "999K views"}, {1_234_567, "1.2M views"}, {12_345_678, "12M views"}, {345_000_000, "345M views"}, {1_234_567_890, "1.2B views"}}) {
		label := views_label(c.views)
		testing.expect_value(t, label, c.label)
		delete(label)
	}
}

@(test)
served_view_text_becomes_a_count :: proc(t: ^testing.T) {
	for c in ([]struct {
			text:  string,
			views: u64,
		}{{"179K views", 179_000}, {"1.1M views", 1_100_000}, {"1,234,567 views", 1_234_567}, {"12 views", 12}, {"1 view", 1}, {"No views", 0}, {"", 0}, {"views", 0}}) {testing.expect_value(t, views_count(c.text), c.views)}
}

@(test)
card_meta_joins_views_and_the_relative_date :: proc(t: ^testing.T) {
	joined := video_meta(1_234_567, " Streamed 2 years ago ")
	defer delete(joined)
	testing.expect_value(t, joined, "1.2M views · Streamed 2 years ago")
	only_date := video_meta(0, "2 years ago")
	defer delete(only_date)
	testing.expect_value(t, only_date, "2 years ago")
}
