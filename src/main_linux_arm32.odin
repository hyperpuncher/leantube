package main

import clay "../vendor/clay"
import "./model"
import yt "./youtube"
import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import sdl "vendor:sdl3"

APP_ID :: "org.hyperpuncher.odin.tv.prototype"
APP_VERSION :: #config(APP_VERSION, "dev")
Callback :: #type proc "c" (_: rawptr, _: rawptr, _: rawptr) -> bool
foreign import bridge "system:tv_bridge"
foreign bridge {
	tv_bus_start :: proc(app_id: cstring) -> bool ---
	tv_send :: proc(uri, payload: cstring, callback: Callback, data: rawptr) -> bool ---
	tv_payload :: proc(message: rawptr) -> cstring ---
	tv_poll :: proc() ---
	tv_attach_window :: proc(app_id: cstring, display, surface: rawptr) -> bool ---
	tv_attach_media :: proc(app_id, media_id, video_data: cstring) -> bool ---
	tv_update_media :: proc(video_data: cstring) ---
	tv_clay_abi :: proc(command_size, config_size, error_size: u32) -> bool ---
	tv_release_media :: proc() ---
	tv_raise :: proc() ---
	tv_closing :: proc() -> bool ---
	tv_visible :: proc() -> bool ---
	tv_shutdown :: proc() ---
}
registered: bool
unloaded: bool
media_id: string
video_metadata: []u8
video_frame_rate: f64
video_seen: bool
load_replied: bool

send :: proc(endpoint: cstring, payload: string, kind: Request_Kind) -> bool {
	body := strings.clone_to_cstring(payload)
	defer delete(body)
	if !tv_send(
		endpoint,
		body,
		reply,
		rawptr(uintptr(kind)),
	) {fmt.eprintln("request send failed; kind:", kind); return false}
	return true
}
command :: proc(endpoint: cstring, extra: string = "", kind: Request_Kind = .Control) -> bool {
	if media_id == "" {return false}
	body := fmt.aprintf("{{\"mediaId\":\"%s\"%s}}", media_id, extra)
	defer delete(body)
	return send(endpoint, body, kind)
}
foreground :: proc() {
	body := fmt.aprintf("{{\"connectionId\":\"%s\"}}", media_id)
	defer delete(body)
	send("luna://com.webos.media/notifyForeground", body, .Foreground)
}
reply :: proc "c" (bus, message, data: rawptr) -> bool {
	context = runtime.default_context()
	value, error := json.parse(string(tv_payload(message)))
	if error != .None {fmt.eprintln("invalid service JSON"); return true}
	defer json.destroy_value(value)
	root, ok := value.(json.Object)
	if !ok {return true}
	kind := Request_Kind(uintptr(data))
	if kind == .Load {load_replied = true}
	if success, found := root["returnValue"].(json.Boolean); found {
		fmt.printf("reply kind=%v accepted=%v\n", kind, bool(success))
		if !bool(success) {
			if kind == .Seek {timeline.seek_target_ms = -1}
			if kind == .Load {notice = "video could not be loaded"; return_to_grid = true}
			if code, valid := model.number(root["errorCode"]); valid {
				fmt.println("request error code:", code)
			}
			return true
		}
		if kind == .Register {registered = true}
		if kind == .Unload {unloaded = true}
	}
	if kind == .Register {
		if event, found := root["event"].(json.String); found {
			fmt.println("app lifecycle:", string(event))
			if event == "close" {running = false}
			if event == "relaunch" {tv_raise()}
		}
	}
	if kind == .Load && media_id == "" {
		if id, found := root["mediaId"].(json.String); found {
			media_id = strings.clone(string(id))
			fmt.println("media session:", media_id)
			command("luna://com.webos.media/subscribe", "", .Subscribe)
			foreground()
			command("luna://com.webos.media/play")
		}
	}
	if kind == .Subscribe {
		if info, found := root["videoInfo"].(json.Object); found {
			width, w_ok := model.number(info["width"])
			height, h_ok := model.number(info["height"])
			if w_ok && h_ok && width > 0 && height > 0 {
				if stream_width != int(width) || stream_height != int(height) {
					stream_width = int(width)
					stream_height = int(height)
					dirty = true
					fmt.printf(
						"video %dx%d after %d ms\n",
						int(width),
						int(height),
						sdl.GetTicks() - playback_requested_at,
					)
				}
			}
			fps, f_ok := model.number(info["frameRate"])
			if f_ok && fps > 0 {video_frame_rate = fps}
			if w_ok && h_ok && f_ok && !video_seen {
				video_seen = true
				fmt.printf("first video after %d ms\n", sdl.GetTicks() - playback_requested_at)
			}
			scan, s_ok := info["scanType"].(json.String)
			if w_ok && h_ok && video_frame_rate > 0 && s_ok && scan == "progressive" {
				metadata := struct {
					ctx:     string `json:"context"`,
					content: string,
					video:   struct {
						frameRate:     f64,
						scanType:      string,
						width, height: i64,
						path:          string,
					},
				} {
					ctx     = media_id,
					content = "movie",
					video   = {
						video_frame_rate,
						"VIDEO_PROGRESSIVE",
						i64(width),
						i64(height),
						"network",
					},
				}
				delete(video_metadata)
				encoded, err := json.marshal(metadata)
				if err == nil {
					video_metadata = encoded
					if loaded {
						update := strings.clone_to_cstring(string(encoded))
						tv_update_media(update)
						delete(update)
					}
				}
			} else {fmt.eprintln("unsupported video metadata")}
		}
		if _, found := root["playing"]; found {paused = false; dirty = true}
		if _, found := root["paused"]; found {paused = true; dirty = true}
		if source, found := root["sourceInfo"].(json.Object); found {
			duration_ms = model.source_duration(source)
			fmt.printf("source duration_ms=%.0f\n", duration_ms)
			dirty = true
		}
		if _, found := root["loadCompleted"]; found {
			loaded = true
			fmt.println("native load completed")
			id := strings.clone_to_cstring(media_id)
			metadata := strings.clone_to_cstring(string(video_metadata))
			fmt.println("native display attached:", tv_attach_media(APP_ID, id, metadata))
			delete(metadata)
			delete(id)
			foreground()
			command("luna://com.webos.media/play")
		}
		ms, valid := model.number(root["currentTime"])
		if time, found := root["currentTime"].(json.Object);
		   found {ms, valid = model.number(time["currentTime"])}
		if valid {timeline.position_ms = ms; dirty = true}
		if _, found := root["seekDone"]; found {model.seek_done(&timeline); dirty = true}
		if _, found := root["error"]; found {
			fmt.eprintln("native media error event")
			notice = "video playback failed; choose another video"
			return_to_grid = true
		}
		if _, found := root["endOfStream"]; found {return_to_grid = true}
	}
	return true
}
stop_playback :: proc() {
	if media_id != "" {
		unloaded = false
		command("luna://com.webos.media/unload", "", .Unload)
		start := sdl.GetTicks()
		for !unloaded && sdl.GetTicks() - start < 1500 {tv_poll(); sdl.Delay(10)}
		fmt.println("media unload acknowledged:", unloaded)
		if !unloaded {running = false}
	}
	tv_release_media()
	yt.remove_local_hls()
	delete(media_id); media_id = ""
	delete(video_metadata); video_metadata = nil
	video_frame_rate = 0
	video_seen = false
	loaded = false; paused = false; resolving = false
	delete(sponsor_segments); sponsor_segments = nil
	timeline = {
		seek_target_ms = -1,
	}
	browsing = true; return_to_grid = false; dirty = true; library_focus_pending = true
}

start_video :: proc() {
	if selected < 0 || selected >= len(catalog.videos) {return}
	resolve_selected()
}

load_video :: proc(url: string) {
	request := struct {
		uri:     string,
		kind:    string `json:"type"`,
		payload: struct {
			option: struct {
				appId: string,
			},
		},
	} {
		uri = url,
		kind = "media",
		payload = {option = {APP_ID}},
	}
	load, error := json.marshal(request)
	if error != nil {browsing = true; notice = "video request failed"; dirty = true; return}
	defer delete(load)
	notice = ""
	browsing = false; paused = false; loaded = false; load_replied = false
	timeline = {
		seek_target_ms = -1,
	}; rate = 1
	duration_ms = catalog.videos[selected].duration_ms
	dirty = true
	if !send(
		"luna://com.webos.media/load",
		string(load),
		.Load,
	) {browsing = true; notice = "video request failed"; return}
	// Serialize opening and closing. Do not start a second session while the
	// first load response is pending. SDL keeps input queued during this wait.
	start := sdl.GetTicks()
	for !load_replied &&
	    running &&
	    !tv_closing() &&
	    sdl.GetTicks() - start < 3000 {tv_poll(); sdl.Delay(10)}
	if !load_replied {fmt.eprintln("media load response timed out"); running = false}
}

main :: proc() {
	_ = sdl.SetHint(sdl.HINT_VIDEO_DRIVER, "wayland")
	_ = sdl.SetAppMetadata("LeanTube", APP_VERSION, APP_ID)
	if !tv_bus_start(APP_ID) {os.exit(1)}
	window: ^sdl.Window
	renderer: ^sdl.Renderer
	clay_memory: []u8
	defer {
		if search_editing {finish_search_input(window)}
		stop_playback()
		stop_network()
		delete(search_text)
		clear_catalog()
		close_icons()
		close_text()
		if renderer != nil {sdl.DestroyRenderer(renderer)}
		tv_shutdown()
		if window != nil {sdl.DestroyWindow(window)}
		sdl.Quit()
		delete(clay_memory)
		fmt.println("native cleanup completed")
	}
	send(
		"luna://com.webos.applicationManager/registerApp",
		"{\"id\":\"" + APP_ID + "\"}",
		.Register,
	)
	start := sdl.GetTicks()
	for !registered && sdl.GetTicks() - start < 3000 {tv_poll(); sdl.Delay(10)}
	if !registered {fmt.eprintln("registration failed"); return}
	if !sdl.Init({.VIDEO}) {fmt.eprintln("SDL init failed:", sdl.GetError()); return}
	window = create_window()
	if window == nil {fmt.eprintln("window failed:", sdl.GetError()); return}
	properties := sdl.GetWindowProperties(window)
	if !tv_attach_window(
		APP_ID,
		sdl.GetPointerProperty(properties, sdl.PROP_WINDOW_WAYLAND_DISPLAY_POINTER, nil),
		sdl.GetPointerProperty(properties, sdl.PROP_WINDOW_WAYLAND_SURFACE_POINTER, nil),
	) {fmt.eprintln("LG window role is unavailable"); return}
	renderer = sdl.CreateRenderer(window, "opengles2")
	if renderer == nil {fmt.eprintln("renderer failed:", sdl.GetError()); return}
	if !tv_clay_abi(
		u32(size_of(clay.RenderCommand)),
		u32(size_of(clay.ElementDeclaration)),
		u32(size_of(clay.ErrorData)),
	) {fmt.eprintln("Clay ABI mismatch"); return}
	clay.SetMaxElementCount(512)
	clay.SetMaxMeasureTextCacheWordCount(2048)
	clay_memory = make([]u8, int(clay.MinMemorySize()))
	clay.Initialize(
		clay.CreateArenaWithCapacityAndMemory(uint(len(clay_memory)), raw_data(clay_memory)),
		{},
		{handler = clay_error},
	)
	clay.SetMeasureTextFunction(measure_text, nil)
	if !sdl.SetRenderDrawBlendMode(renderer, sdl.BLENDMODE_BLEND) {return}
	path, path_error := os.get_executable_path(context.allocator)
	if path_error != nil {return}
	defer delete(path)
	app_directory = filepath.dir(path)
	if !open_text(renderer) {fmt.eprintln("UI assets failed:", sdl.GetError()); return}
	if start_network() {
		start_search()
	} else {
		notice = "network is unavailable"
	}
	if !render(renderer) {fmt.eprintln("frame failed:", sdl.GetError()); return}
	fmt.println("video grid presented")
	previous_frame := sdl.GetTicks()
	for running && !tv_closing() {
		tv_poll()
		if return_to_grid {stop_playback()}
		wheel: f32
		event: sdl.Event
		if sdl.WaitEventTimeout(&event, 20) {
			// SDL documents draining the queue after the blocking wait.
			for {
				wheel += handle_event(renderer, event)
				if !sdl.PollEvent(&event) {break}
			}
		}
		poll_network(renderer)
		poll_login_tick()
		auto_skip_sponsor()
		now := sdl.GetTicks()
		frame_dt := f32(min(now - previous_frame, 50)) / 1000
		previous_frame = now
		if !tv_visible() {running = false}
		if dirty {if !render(renderer, wheel, frame_dt) {break}; dirty = false}
	}
	fmt.println("player stopping")
}
