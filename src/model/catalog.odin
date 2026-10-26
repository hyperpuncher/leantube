package model

import "core:fmt"
import "core:strings"

GRID_COLUMNS :: 3
Video :: struct {
	duration_ms:                        f64,
	id, title, channel, duration_label: string,
	browse_id, thumbnail_url:           string,
}
Catalog :: struct {
	query:        string,
	videos:       [dynamic]Video,
	continuation: string,
}

QUALITY_TIERS := [?]struct {
	short_side: int,
	label:      string,
} {
	{144, "144p"},
	{240, "240p"},
	{360, "360p"},
	{480, "480p"},
	{720, "720p"},
	{1080, "1080p"},
	{1440, "1440p"},
	{2160, "2160p"},
}

// The short side identifies the quality tier. Wide films such as 1920x804
// are 1080p uploads, not 804p.
quality_tier_index :: proc(width, height: int) -> int {
	if width <= 0 || height <= 0 {return -1}
	short_side := min(width, height)
	for tier, index in QUALITY_TIERS {
		if short_side <= tier.short_side {return index}
	}
	return len(QUALITY_TIERS) - 1
}

quality_label :: proc(width, height: int) -> string {
	index := quality_tier_index(width, height)
	return index >= 0 ? QUALITY_TIERS[index].label : ""
}


time_label :: proc(ms: f64, zero: string = "00:00") -> string {
	if ms <= 0 {return strings.clone(zero)}
	seconds := i64(ms / 1000)
	if seconds >=
	   3600 {return fmt.aprintf("%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)}
	return fmt.aprintf("%02d:%02d", seconds / 60, seconds % 60)
}

video_destroy :: proc(video: ^Video) {
	delete(video.id); delete(video.title); delete(video.channel); delete(video.duration_label)
	delete(video.browse_id); delete(video.thumbnail_url)
	video^ = {}
}

catalog_destroy :: proc(catalog: ^Catalog) {
	for &video in catalog.videos {video_destroy(&video)}
	delete(catalog.videos)
	delete(catalog.query)
	delete(catalog.continuation)
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
