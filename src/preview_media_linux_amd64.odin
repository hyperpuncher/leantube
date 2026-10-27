package main

import "./model"
import "core:fmt"
import sdl "vendor:sdl3"

DEV_SMOKE :: #config(DEV_SMOKE, false)

start_text_input :: proc(window: ^sdl.Window) -> bool {return(
		window == nil ||
		sdl.StartTextInput(window) \
	)}
stop_text_input :: proc(window: ^sdl.Window) {if window != nil {_ = sdl.StopTextInput(window)}}

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

load_video :: proc(_: string) {start_video()}

start_video :: proc() {
	if selected < 0 || selected >= len(catalog.videos) {return}
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
	resolving = false
	delete(sponsor_segments); sponsor_segments = nil
	return_to_grid = false
	library_focus_pending = true
	dirty = true
}

run_dev :: proc(renderer: ^sdl.Renderer) {
	fmt.println("local UI preview only; no TV commands or media playback")
	fmt.println("arrows: select / seek / rate; enter: open / pause; escape: back / close")
	assert(render(renderer), string(sdl.GetError()))
	dirty = false
	started := sdl.GetTicks()
	for running {
		wheel: f32
		event: sdl.Event
		if sdl.WaitEventTimeout(&event, 100) {wheel = handle_event(renderer, event)}
		if return_to_grid {stop_playback()}
		poll_network(renderer)
		expire_player_controls()
		if timeline.seek_target_ms >= 0 {
			timeline.position_ms = timeline.seek_target_ms
			model.seek_done(&timeline)
		}
		if dirty {
			assert(render(renderer, wheel), string(sdl.GetError()))
			dirty = false
		}
		if DEV_SMOKE {
			assert(sdl.GetTicks() - started < 15000, "native search UI startup timed out")
			if !search_loading {
				assert(len(catalog.videos) > 0, "native search returned no videos")
				for texture in textures {
					if texture !=
					   nil {fmt.println("native search, cover upload, and Wayland UI passed"); return}
				}
			}
		}
	}
}
