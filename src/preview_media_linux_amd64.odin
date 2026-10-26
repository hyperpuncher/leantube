package main

import "./model"
import "core:fmt"
import sdl "vendor:sdl3"

DEV_SMOKE :: #config(DEV_SMOKE, false)

// The host has no LG media service. These are UI-only responses; no stream
// request is read and no audio or video playback is started.
command :: proc(endpoint: cstring, _: string = "", _: Request_Kind = .Control) -> bool {
	switch string(endpoint) {
	case "luna://com.webos.media/play":
		paused = false
	case "luna://com.webos.media/pause":
		paused = true
	}
	return true
}

start_video :: proc() {
	browsing = false
	loaded = true
	paused = true
	duration_ms = catalog.videos[selected].duration_ms
	timeline = {
		seek_target_ms = -1,
	}
	rate = 1
	dirty = true
}

stop_playback :: proc() {
	browsing = true
	return_to_grid = false
	library_focus_pending = true
	dirty = true
}

run_dev :: proc(renderer: ^sdl.Renderer) {
	fmt.println("local UI preview only; no TV commands or media playback")
	fmt.println("arrows: select / seek / rate; enter: open / pause; escape: back / close")
	assert(render(renderer), string(sdl.GetError()))
	dirty = false
	when DEV_SMOKE {fmt.println("local Wayland UI startup passed"); return}
	for running {
		wheel: f32
		event: sdl.Event
		if sdl.WaitEventTimeout(&event, 100) {wheel = handle_event(renderer, event)}
		if return_to_grid {stop_playback()}
		if timeline.seek_target_ms >= 0 {
			timeline.position_ms = timeline.seek_target_ms
			model.seek_done(&timeline)
		}
		if dirty {
			assert(render(renderer, wheel), string(sdl.GetError()))
			dirty = false
		}
	}
}
