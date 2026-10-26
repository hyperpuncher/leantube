package main

import "./model"
import sb "./sponsorblock"
import "core:fmt"
import sdl "vendor:sdl3"

key :: proc(code: sdl.Keycode, window: ^sdl.Window = nil) {
	if browsing && search_key(code, window) {return}
	if browsing {
		library_focus_pending = true
		switch code {
		case sdl.K_ESCAPE, sdl.K_AC_BACK:
			running = false
		case sdl.K_RETURN, sdl.K_SPACE, sdl.K_KP_ENTER:
			start_video()
		case sdl.K_LEFT:
			selected = model.grid_move(selected, len(catalog.videos), -1, 0, grid_columns)
		case sdl.K_RIGHT:
			selected = model.grid_move(selected, len(catalog.videos), 1, 0, grid_columns)
		case sdl.K_UP:
			selected = model.grid_move(selected, len(catalog.videos), 0, -1, grid_columns)
		case sdl.K_DOWN:
			selected = model.grid_move(selected, len(catalog.videos), 0, 1, grid_columns)
		}
	} else {
		switch code {
		case sdl.K_ESCAPE, sdl.K_AC_BACK:
			return_to_grid = true
		case sdl.K_RETURN, sdl.K_SPACE, sdl.K_KP_ENTER:
			if paused {command("luna://com.webos.media/play")} else {command("luna://com.webos.media/pause")}
		case sdl.K_LEFT, sdl.K_RIGHT:
			offset: f64 = code == sdl.K_RIGHT ? 10000 : -10000
			target := model.seek_target(timeline, offset, duration_ms)
			seek_to(target)
		case sdl.K_UP, sdl.K_DOWN:
			delta: f64 = code == sdl.K_DOWN ? -0.25 : 0.25
			rate = clamp(rate + delta, 0.5, 2)
			extra := fmt.aprintf(",\"playRate\":%.2f,\"audioOutput\":true", rate)
			command("luna://com.webos.media/setPlayRate", extra)
			delete(extra)
		}
	}
	dirty = true
}

seek_to :: proc(target: f64) -> bool {
	extra := fmt.aprintf(",\"position\":%d", i64(target))
	defer delete(extra)
	if !command("luna://com.webos.media/seek", extra, .Seek) {return false}
	timeline.seek_target_ms = target
	return true
}

auto_skip_sponsor :: proc() {
	if browsing || !loaded || paused || timeline.seek_target_ms >= 0 {return}
	from := timeline.position_ms
	target := sb.skip_target(sponsor_segments[:], from, duration_ms)
	if target >= 0 && seek_to(target) {sb.mark_skipped(sponsor_segments[:], from, target)}
}
