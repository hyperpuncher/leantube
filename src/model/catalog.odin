package model

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "core:testing"

GRID_COLUMNS :: 3
MAX_VIDEOS :: 6
Video :: struct {
	duration_ms:                                              f64,
	title_label, player_label, channel_label, duration_label: string,
}
Catalog :: struct {
	query:  string,
	videos: [dynamic]Video,
}

// Fit labels to SDL's ASCII-only debug font.
ascii_label :: proc(text: string, columns: int) -> string {
	buffer: [128]u8
	limit := clamp(columns, 0, len(buffer))
	used := 0
	for r in text {
		if used == limit {
			if limit >= 3 {
				buffer[limit - 3] = '.'
				buffer[limit - 2] = '.'
				buffer[limit - 1] = '.'
			}
			break
		}
		buffer[used] = r < 32 ? ' ' : (r <= 126 ? u8(r) : u8('?'))
		used += 1
	}
	return strings.clone(string(buffer[:used]))
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
		delete(video.title_label); delete(video.player_label)
		delete(video.channel_label); delete(video.duration_label)
	}
	delete(catalog.videos)
	delete(catalog.query)
	catalog^ = {}
}

catalog_parse :: proc(data: string) -> (Catalog, bool) {
	source: struct {
		query:  string,
		videos: []struct {
			id, title, channel: string,
			duration_ms:        f64,
		},
	}
	defer {
		for video in source.videos {
			delete(video.id)
			delete(video.title)
			delete(video.channel)
		}
		delete(source.videos)
		delete(source.query)
	}
	if json.unmarshal_string(data, &source) != nil {return {}, false}
	if len(source.videos) == 0 || len(source.videos) > MAX_VIDEOS {return {}, false}

	catalog: Catalog
	ok := false
	defer {if !ok {catalog_destroy(&catalog)}}
	catalog.query = ascii_label(source.query, 72)
	for video in source.videos {
		if len(video.id) != 11 || video.title == "" || video.duration_ms < 0 {return {}, false}
		for ch in video.id {
			if !(ch >= 'a' && ch <= 'z' ||
				   ch >= 'A' && ch <= 'Z' ||
				   ch >= '0' && ch <= '9' ||
				   ch == '_' ||
				   ch == '-') {return {}, false}
		}
		append(
			&catalog.videos,
			Video {
				duration_ms = video.duration_ms,
				title_label = ascii_label(video.title, 21),
				player_label = ascii_label(video.title, 24),
				channel_label = ascii_label(video.channel, 16),
				duration_label = time_label(video.duration_ms, "--:--"),
			},
		)
	}
	ok = true
	return catalog, true
}

// Stay in the current row at horizontal edges. Down selects the last card
// when the final row is incomplete. Selection never wraps or leaves the grid.
grid_move :: proc(selected, count, dx, dy: int) -> int {
	if count <= 0 {return 0}
	current := clamp(selected, 0, count - 1)
	row := current / GRID_COLUMNS
	column := clamp(current % GRID_COLUMNS + dx, 0, GRID_COLUMNS - 1)
	if dy != 0 {row = clamp(row + dy, 0, (count - 1) / GRID_COLUMNS)}
	return min(row * GRID_COLUMNS + column, count - 1)
}

@(test)
catalog_owns_metadata_and_bounds_labels :: proc(t: ^testing.T) {
	catalog, ok := catalog_parse(
		`{"query":"open films","videos":[{"id":"aqz-KE-bpKQ","title":"Big Buck Bunny","channel":"Blender","duration_ms":634578}]}`,
	)
	defer catalog_destroy(&catalog)
	if !testing.expect(t, ok) {return}
	testing.expect_value(t, catalog.videos[0].duration_label, "10:34")
	testing.expect_value(t, catalog.videos[0].title_label, "Big Buck Bunny")
	label := ascii_label("long title here", 8)
	defer delete(label)
	testing.expect_value(t, label, "long ...")
	unicode := ascii_label("café\nfilm", 20)
	defer delete(unicode)
	testing.expect_value(t, unicode, "caf? film")
}

@(test)
catalog_rejects_invalid_or_empty_data :: proc(t: ^testing.T) {
	fixtures := []string {
		`{}`,
		`{"query":"x","videos":[]}`,
		`{"query":"x","videos":[null]}`,
		`{"query":"x","videos":[{"id":"../private","title":"x","channel":"y","duration_ms":1}]}`,
		`{"query":"x","videos":[{"id":"aqz-KE-bpKQ","title":"x","channel":"y","duration_ms":1},{"id":42}]}`,
	}
	for fixture in fixtures {
		catalog, ok := catalog_parse(fixture)
		testing.expect(t, !ok)
		catalog_destroy(&catalog)
	}
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
}
