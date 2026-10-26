package model

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "core:testing"

GRID_COLUMNS :: 3
MAX_VIDEOS :: 24
Video :: struct {
	duration_ms:                    f64,
	title, channel, duration_label: string,
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
		delete(video.title); delete(video.channel); delete(video.duration_label)
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
	catalog.query = strings.clone(source.query)
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
				title = strings.clone(video.title),
				channel = strings.clone(video.channel),
				duration_label = time_label(video.duration_ms, "--:--"),
			},
		)
	}
	ok = true
	return catalog, true
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
catalog_owns_metadata_and_preserves_unicode :: proc(t: ^testing.T) {
	catalog, ok := catalog_parse(
		`{"query":"cinéma","videos":[{"id":"aqz-KE-bpKQ","title":"café: a title longer than the old ASCII limit","channel":"créateurs","duration_ms":634578}]}`,
	)
	defer catalog_destroy(&catalog)
	if !testing.expect(t, ok) {return}
	testing.expect_value(t, catalog.query, "cinéma")
	testing.expect_value(t, catalog.videos[0].duration_label, "10:34")
	testing.expect_value(
		t,
		catalog.videos[0].title,
		"café: a title longer than the old ASCII limit",
	)
	testing.expect_value(t, catalog.videos[0].channel, "créateurs")
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
catalog_accepts_a_full_page_but_rejects_overflow :: proc(t: ^testing.T) {
	Entry :: struct {
		id, title: string,
	}
	entries := make([]Entry, MAX_VIDEOS + 1)
	defer delete(entries)
	for &entry in entries {entry = {"aqz-KE-bpKQ", "video"}}
	counts := [2]int{MAX_VIDEOS, MAX_VIDEOS + 1}
	for count in counts {
		source := struct {
			videos: []Entry,
		} {
			videos = entries[:count],
		}
		data, error := json.marshal(source)
		if !testing.expect_value(t, error, nil) {return}
		catalog, ok := catalog_parse(string(data))
		testing.expect_value(t, ok, count == MAX_VIDEOS)
		if ok {testing.expect_value(t, len(catalog.videos), count)}
		catalog_destroy(&catalog)
		delete(data)
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
	testing.expect_value(t, grid_move(1, 6, 0, 1, 2), 3)
	testing.expect_value(t, grid_move(4, 6, 0, -1, 2), 2)
	testing.expect_value(t, grid_move(1, 6, 0, 1, 1), 2)
}
