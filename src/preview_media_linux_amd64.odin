package main

import "./model"
import yt "./youtube"
import "core:fmt"
import sdl "vendor:sdl3"

DEV_SMOKE :: #config(DEV_SMOKE, false)

start_text_input :: proc(window: ^sdl.Window) -> bool {return(
		window == nil ||
		sdl.StartTextInput(window) \
	)}
stop_text_input :: proc(window: ^sdl.Window) {if window != nil {_ = sdl.StopTextInput(window)}}
update_text_input :: proc() {}

// The host has no LG media service. These are UI-only responses; no stream
// request is read and no audio or video playback is started.
player_pause :: proc(value: bool) -> bool {paused = value; return true}
player_rate :: proc(_: f64) -> bool {return true}
player_seek :: proc(_: f64) -> bool {return true}

load_video :: proc(
	stream: yt.Stream,
	_: ^sdl.Renderer,
	position_ms: f64 = 0,
	start_paused: bool = false,
) {
	start_video()
	if stream.duration_ms > 0 {duration_ms = stream.duration_ms}
	timeline.position_ms = position_ms
	paused = start_paused
}

start_video :: proc() {
	if selected < 0 || selected >= len(catalog.videos) {return}
	browsing = false
	loaded = true
	paused = true
	duration_ms = catalog.videos[selected].duration_ms
	timeline = {
		position_ms    = model.video_resume_position(catalog.videos[selected]),
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
	fmt.println(
		"arrows: select / seek / rate; enter: open / pause; escape: back; close the window to exit",
	)
	assert(render(renderer), string(sdl.GetError()))
	dirty = false
	started := sdl.GetTicks()
	for running {
		wheel: f32
		event: sdl.Event
		if sdl.WaitEventTimeout(
			&event,
			loading_active() ? 16 : 100,
		) {wheel = handle_event(renderer, event)}
		if return_to_grid {stop_playback()}
		poll_network(renderer)
		poll_card_press(sdl.GetTicks())
		poll_login_tick()
		expire_player_controls()
		expire_toast(sdl.GetTicks())
		if timeline.seek_target_ms >= 0 {
			timeline.position_ms = timeline.seek_target_ms
			model.seek_done(&timeline)
		}
		if dirty || loading_active() {
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
