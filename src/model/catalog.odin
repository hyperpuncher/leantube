package model

import "core:fmt"
import "core:sort"
import "core:strconv"
import "core:strings"

GRID_COLUMNS :: 3
Video :: struct {
	duration_ms:                        f64,
	id, title, channel, duration_label: string,
	meta:                               string,
	published_age_s:                    i64,
	// Original feed position, kept stable when the display order changes.
	cover_index:                        int,
	browse_id, thumbnail_url:           string,
	actions:                            [dynamic]Card_Action,
}
Catalog :: struct {
	query:        string,
	videos:       [dynamic]Video,
	continuation: string,
	channel:      Channel,
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


// Convert a relative card label such as "Streamed 2 days ago" to seconds.
// Unknown labels return false and sort after known dates.
relative_age :: proc(text: string) -> (seconds: i64, ok: bool) {
	trimmed := strings.trim_space(text)
	if trimmed == "just now" {return 0, true}
	if !strings.has_suffix(trimmed, "ago") {return}
	fields := strings.fields(strings.trim_space(strings.trim_suffix(trimmed, "ago")))
	defer delete(fields)
	if len(fields) < 2 {return}
	count, parsed := strconv.parse_i64(fields[len(fields) - 2])
	if !parsed || count < 0 {return}
	multiplier: i64
	switch {
	case strings.has_prefix(fields[len(fields) - 1], "second"):
		multiplier = 1
	case strings.has_prefix(fields[len(fields) - 1], "minute"):
		multiplier = 60
	case strings.has_prefix(fields[len(fields) - 1], "hour"):
		multiplier = 60 * 60
	case strings.has_prefix(fields[len(fields) - 1], "day"):
		multiplier = 24 * 60 * 60
	case strings.has_prefix(fields[len(fields) - 1], "week"):
		multiplier = 7 * 24 * 60 * 60
	case strings.has_prefix(fields[len(fields) - 1], "month"):
		multiplier = 30 * 24 * 60 * 60
	case strings.has_prefix(fields[len(fields) - 1], "year"):
		multiplier = 365 * 24 * 60 * 60
	case:
		return
	}
	return count * multiplier, true
}

// Views arrive as text such as "179K views", "1,234,567 views" or "1.1M views".
// Return 0 for "No views" and for anything unreadable.
views_count :: proc(text: string) -> u64 {
	suffix := strings.trim_suffix(strings.trim_suffix(text, " views"), " view")
	number := suffix
	scale: f64 = 1
	if len(number) > 0 {
		switch number[len(number) - 1] {
		case 'K':
			scale = 1_000
		case 'M':
			scale = 1_000_000
		case 'B', 'G':
			scale = 1_000_000_000
		}
		if scale > 1 {number = number[:len(number) - 1]}
	}
	value, fraction: f64
	fraction_scale: f64 = 1
	seen_digit, seen_dot := false, false
	for r in number {
		switch {
		case r >= '0' && r <= '9':
			if seen_dot {
				fraction_scale *= 10
				fraction += f64(r - '0') / fraction_scale
			} else {
				value = value * 10 + f64(r - '0')
			}
			seen_digit = true
		case r == ',', r == ' ':
		case r == '.' && !seen_dot:
			seen_dot = true
		case:
			return 0
		}
	}
	value += fraction
	if !seen_digit {return 0}
	return u64(value * scale + 0.5)
}

// Round to the nearest shown unit: 987, 12K, 1.2M, 345M, 1.5B.
views_label :: proc(views: u64) -> string {
	if views == 0 {return ""}
	if views < 1_000 {return fmt.aprintf("%d views", views)}
	value: f64
	unit: byte
	switch {
	case views < 1_000_000:
		value, unit = f64(views) / 1_000, 'K'
	case views < 1_000_000_000:
		value, unit = f64(views) / 1_000_000, 'M'
	case:
		value, unit = f64(views) / 1_000_000_000, 'B'
	}
	return fmt.aprintf(value < 9.95 ? "%.1f%c views" : "%.0f%c views", value, unit)
}

// One caption line for a card, for example "1.2M views · 2 years ago".
video_meta :: proc(views: u64, published: string) -> string {
	views_text := views_label(views)
	defer delete(views_text)
	relative := strings.trim_space(published)
	if views_text == "" {return strings.clone(published)}
	if relative == "" {return strings.clone(views_text)}
	return fmt.aprintf("%s · %s", views_text, relative)
}

// Newest video first. Unknown dates stay after dated cards. Equal ages keep
// their incoming order, so a tie is not reordered.
sort_latest :: proc(videos: []Video) {
	sort.merge_sort_proc(videos, proc(a, b: Video) -> int {
		a_known := a.published_age_s >= 0
		b_known := b.published_age_s >= 0
		switch {
		case a_known && !b_known:
			return -1
		case !a_known && b_known:
			return 1
		case !a_known:
			return 0
		}
		if a.published_age_s < b.published_age_s {return -1}
		if a.published_age_s > b.published_age_s {return 1}
		return 0
	})
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
	delete(video.browse_id); delete(video.thumbnail_url); delete(video.meta)
	card_actions_destroy(&video.actions)
	video^ = {}
}

catalog_destroy :: proc(catalog: ^Catalog) {
	for &video in catalog.videos {video_destroy(&video)}
	delete(catalog.videos)
	delete(catalog.query)
	delete(catalog.continuation)
	channel_destroy(&catalog.channel)
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
