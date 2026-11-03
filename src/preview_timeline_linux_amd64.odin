package main

import clay "../vendor/clay"
import "./model"
import sb "./sponsorblock"
import "core:math"
import sdl "vendor:sdl3"

check_timeline_pixel :: proc(
	surface: ^sdl.Surface,
	fraction: f32,
	expected: clay.Color,
	vertical_fraction: f32 = 0.5,
) {
	track := clay.GetElementData(clay.ID("timeline-track")).boundingBox
	red, green, blue: u8
	assert(
		sdl.ReadSurfacePixel(
			surface,
			i32(track.x + track.width * fraction),
			i32(track.y + track.height * vertical_fraction),
			&red,
			&green,
			&blue,
			nil,
		),
	)
	// Translucent segments blend with the fade and lower track layers.
	// A sponsor marker sits over the gray track or buffer, not the progress.
	alpha := f32(TIMELINE_ALPHA) / 255
	background_max := expected == COLOR_SPONSOR ? COLOR_BUFFERED[0] : 255
	for value, i in ([3]u8{red, green, blue}) {
		low := expected[i] * alpha
		high := low + background_max * (1 - alpha)
		assert(
			f32(value) >= math.floor(low) - 1 && f32(value) <= math.ceil(high) + 1,
			"timeline marker or progress color is incorrect",
		)
	}
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
	track := clay.GetElementData(clay.ID("timeline-track")).boundingBox
	marker := clay.GetElementData(clay.ID("sponsor-marker", 1)).boundingBox
	assert(math.abs(marker.x - (track.x + track.width * 0.4)) < 0.1)
	assert(math.abs(marker.width - track.width * 0.2) < 0.1)
	assert(marker.y == track.y && marker.height == scaled(TIMELINE_TRACK))
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

check_buffered_timeline :: proc(renderer: ^sdl.Renderer, surface: ^sdl.Surface) {
	original_time, original_duration := timeline, duration_ms
	original_paused, original_until := paused, controls_until
	defer {
		timeline, duration_ms = original_time, original_duration
		paused, controls_until = original_paused, original_until
		delete(sponsor_segments); sponsor_segments = nil
		clay.SetPointerState({-1, -1}, false)
	}
	duration_ms = 100000
	timeline = {
		position_ms    = 10000,
		seek_target_ms = -1,
	}
	_ = model.set_buffered_range(&timeline, 10000, 30000, duration_ms)
	append(&sponsor_segments, {start_ms = 20000, end_ms = 25000})
	clay.SetPointerState({-1, -1}, false)
	snapshot(renderer, surface, "player-buffered")
	idle_track := clay.GetElementData(clay.ID("timeline-track")).boundingBox
	idle_knob := clay.GetElementData(clay.ID("timeline-knob")).boundingBox
	hit := clay.GetElementData(clay.ID("timeline")).boundingBox
	assert(hit.height == scaled(TIMELINE_HEIGHT))
	assert(idle_track.height == scaled(TIMELINE_TRACK))
	assert(idle_knob.width == scaled(TIMELINE_KNOB))
	check_timeline_pixel(surface, 0.05, COLOR_ACCENT)
	check_timeline_pixel(surface, 0.15, COLOR_BUFFERED)
	check_timeline_pixel(surface, 0.225, COLOR_SPONSOR)
	check_timeline_pixel(surface, 0.275, COLOR_BUFFERED)
	check_timeline_pixel(surface, 0.35, COLOR_TRACK)
	buffer := clay.GetElementData(clay.ID("timeline-buffered")).boundingBox
	assert(math.abs(buffer.x - (idle_track.x + idle_track.width * 0.1)) < 0.1)
	assert(math.abs(buffer.width - idle_track.width * 0.2) < 0.1)

	// The whole hit area responds, not only the thin painted line.
	x, y := hit.x + hit.width * 0.75, hit.y + hit.height - 1
	controls_pointer(renderer, x, y, false, false)
	snapshot(renderer, surface, "player-timeline-hover")
	hover_track := clay.GetElementData(clay.ID("timeline-track")).boundingBox
	hover_knob := clay.GetElementData(clay.ID("timeline-knob")).boundingBox
	assert(hover_track.height == scaled(TIMELINE_TRACK_HOVER))
	assert(hover_knob.width == scaled(TIMELINE_KNOB_HOVER))
	assert(clay.GetElementData(clay.ID("timeline")).boundingBox == hit)
	assert(
		math.abs(hover_track.y + hover_track.height / 2 - (idle_track.y + idle_track.height / 2)) <
		0.1,
	)
	assert(
		math.abs(hover_knob.x + hover_knob.width / 2 - (idle_knob.x + idle_knob.width / 2)) < 0.1,
	)
	assert(
		clay.GetElementData(clay.ID("sponsor-marker", 0)).boundingBox.height == hover_track.height,
	)
	check_timeline_pixel(surface, 0.15, COLOR_BUFFERED)
	check_timeline_pixel(surface, 0.225, COLOR_SPONSOR)
	// Both ends must fill their top corners, not form rounded caps.
	marker := clay.GetElementData(clay.ID("sponsor-marker", 0)).boundingBox
	for edge_x in ([2]f32{math.ceil(marker.x), math.floor(marker.x + marker.width) - 2}) {
		check_timeline_pixel(
			surface,
			(edge_x + 0.5 - hover_track.x) / hover_track.width,
			COLOR_SPONSOR,
			(math.ceil(marker.y) + 0.5 - hover_track.y) / hover_track.height,
		)
	}

	paused = false
	controls_until = 1
	expire_player_controls()
	assert(player_controls_visible(), "hover must keep the controls visible")
	controls_pointer(renderer, x, y, true, true)
	assert(math.abs(timeline.seek_target_ms - 75000) < 1, "the full hit area must seek accurately")
	assert(timeline.buffer_start_ms == 0 && timeline.buffer_end_ms == 0)
	paused = true
	clay.SetPointerState({-1, -1}, false)
	snapshot(renderer, surface, "player-timeline-seek")
	assert(!clay.GetElementData(clay.ID("timeline-buffered")).found)
	assert(clay.GetElementData(clay.ID("timeline-track")).boundingBox.height == idle_track.height)

	// The enlarged marker also accepts clicks outside the track's left edge.
	timeline.position_ms, timeline.seek_target_ms = 0, -1
	assert(render(renderer))
	controls_pointer(
		renderer,
		hit.x - scaled(TIMELINE_KNOB) / 4,
		hit.y + hit.height / 2,
		true,
		true,
	)
	assert(timeline.seek_target_ms == 0, "the marker edge must seek to the start")
	duration_ms = 0
	snapshot(renderer, surface, "player-timeline-no-duration")
	assert(!clay.GetElementData(clay.ID("timeline-buffered")).found)
}
