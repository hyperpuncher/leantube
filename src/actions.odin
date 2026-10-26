package main

import "./model"
import "core:fmt"
import sdl "vendor:sdl3"

key :: proc(code: sdl.Keycode) {
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
			extra := fmt.aprintf(",\"position\":%d", i64(target))
			if command(
				"luna://com.webos.media/seek",
				extra,
				.Seek,
			) {timeline.seek_target_ms = target}
			delete(extra)
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
