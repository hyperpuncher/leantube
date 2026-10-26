package main

import clay "../vendor/clay"
import sb "./sponsorblock"
import "core:math"
import sdl "vendor:sdl3"

check_timeline_pixel :: proc(surface: ^sdl.Surface, fraction: f32, expected: clay.Color) {
	track := clay.GetElementData(clay.ID("timeline")).boundingBox
	red, green, blue: u8
	assert(
		sdl.ReadSurfacePixel(
			surface,
			i32(track.x + track.width * fraction),
			i32(track.y + track.height / 2),
			&red,
			&green,
			&blue,
			nil,
		),
	)
	assert(
		red == u8(expected[0]) && green == u8(expected[1]) && blue == u8(expected[2]),
		"timeline marker or progress color is incorrect",
	)
}

check_sponsor_timeline :: proc(renderer: ^sdl.Renderer, surface: ^sdl.Surface) {
	original_duration, original_position := duration_ms, timeline.position_ms
	defer {
		delete(sponsor_segments); sponsor_segments = nil
		duration_ms, timeline.position_ms = original_duration, original_position
	}
	duration_ms, timeline.position_ms = 100000, 15000
	append(
		&sponsor_segments,
		..[]sb.Segment {
			{start_ms = 10000, end_ms = 20000},
			{start_ms = 40000, end_ms = 60000},
			{start_ms = 70000, end_ms = 80000, skipped = true},
			{start_ms = 82000, end_ms = 90000, video_duration_ms = 120000},
			{start_ms = 96000, end_ms = 102000},
		},
	)
	snapshot(renderer, surface, "player-sponsors")
	track := clay.GetElementData(clay.ID("timeline")).boundingBox
	marker := clay.GetElementData(clay.ID("sponsor-marker", 1)).boundingBox
	assert(math.abs(marker.x - (track.x + track.width * 0.4)) < 0.1)
	assert(math.abs(marker.width - track.width * 0.2) < 0.1)
	assert(marker.y == track.y && marker.height == track.height)
	for c in ([]struct {
			fraction: f32,
			color:    clay.Color,
		}{{0.05, COLOR_ACCENT}, {0.125, COLOR_ACCENT}, {0.175, COLOR_SPONSOR}, {0.205, COLOR_TRACK}, {0.395, COLOR_TRACK}, {0.405, COLOR_SPONSOR}, {0.595, COLOR_SPONSOR}, {0.605, COLOR_TRACK}, {0.75, COLOR_TRACK}, {0.85, COLOR_TRACK}, {0.99, COLOR_TRACK}}) {check_timeline_pixel(surface, c.fraction, c.color)}
	sb.mark_skipped(sponsor_segments[:], 10000, 20000)
	snapshot(renderer, surface, "player-sponsor-skipped")
	check_timeline_pixel(surface, 0.175, COLOR_TRACK)
	check_timeline_pixel(surface, 0.5, COLOR_SPONSOR)
	duration_ms = 0
	snapshot(renderer, surface, "player-sponsor-unknown-duration")
	check_timeline_pixel(surface, 0.125, COLOR_TRACK)
	check_timeline_pixel(surface, 0.5, COLOR_TRACK)
}
