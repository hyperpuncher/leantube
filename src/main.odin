package main

import clay "../vendor/clay"
import "./model"
import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import sdl "vendor:sdl3"

APP_ID :: "org.hyperpuncher.odin.tv.prototype"
APP_VERSION :: #config(APP_VERSION, "dev")
Request_Kind :: enum uintptr {
	Register,
	Load,
	Subscribe,
	Foreground,
	Control,
	Seek,
	Unload,
}
Callback :: #type proc "c" (_: rawptr, _: rawptr, _: rawptr) -> bool
foreign import bridge "system:tv_bridge"
foreign bridge {
	tv_bus_start :: proc(app_id: cstring) -> bool ---
	tv_send :: proc(uri, payload: cstring, callback: Callback, data: rawptr) -> bool ---
	tv_payload :: proc(message: rawptr) -> cstring ---
	tv_poll :: proc() ---
	tv_attach_window :: proc(app_id: cstring, display, surface: rawptr) -> bool ---
	tv_attach_media :: proc(app_id, media_id, video_data: cstring) -> bool ---
	tv_clay_abi :: proc(command_size, config_size, error_size: u32) -> bool ---
	tv_release_media :: proc() ---
	tv_raise :: proc() ---
	tv_closing :: proc() -> bool ---
	tv_visible :: proc() -> bool ---
	tv_shutdown :: proc() ---
}
registered: bool
running := true
paused: bool
loaded: bool
unloaded: bool
media_id: string
video_metadata: []u8
timeline := model.Timeline {
	seek_target_ms = -1,
}
duration_ms: f64
rate: f64 = 1
dirty := true
browsing := true
return_to_grid: bool
load_replied: bool
selected: int
catalog: model.Catalog
textures: [model.MAX_VIDEOS]^sdl.Texture
app_directory: string
notice := "arrows: choose   OK: play   Back: close"

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
			fps, f_ok := model.number(info["frameRate"])
			scan, s_ok := info["scanType"].(json.String)
			if w_ok && h_ok && f_ok && s_ok && scan == "progressive" {
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
					video   = {fps, "VIDEO_PROGRESSIVE", i64(width), i64(height), "network"},
				}
				delete(video_metadata)
				encoded, err := json.marshal(metadata)
				if err == nil {
					video_metadata = encoded
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
	delete(media_id); media_id = ""
	delete(video_metadata); video_metadata = nil
	loaded = false; paused = false
	timeline = {
		seek_target_ms = -1,
	}
	browsing = true; return_to_grid = false; dirty = true
}

start_video :: proc() {
	if selected < 0 || selected >= len(catalog.videos) {return}
	path := fmt.aprintf("%s/catalog/%d.json", app_directory, selected)
	defer delete(path)
	load, error := os.read_entire_file(path, context.allocator)
	if error !=
	   nil {notice = "stream request missing; prepare this page again"; dirty = true; return}
	defer delete(load)
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

key :: proc(code: sdl.Keycode) {
	if browsing {
		switch code {
		case sdl.K_ESCAPE, sdl.K_AC_BACK:
			running = false
		case sdl.K_RETURN, sdl.K_SPACE, sdl.K_KP_ENTER:
			start_video()
		case sdl.K_LEFT:
			selected = model.grid_move(selected, len(catalog.videos), -1, 0)
		case sdl.K_RIGHT:
			selected = model.grid_move(selected, len(catalog.videos), 1, 0)
		case sdl.K_UP:
			selected = model.grid_move(selected, len(catalog.videos), 0, -1)
		case sdl.K_DOWN:
			selected = model.grid_move(selected, len(catalog.videos), 0, 1)
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
main :: proc() {
	_ = sdl.SetHint(sdl.HINT_VIDEO_DRIVER, "wayland")
	_ = sdl.SetAppMetadata("LeanTube", APP_VERSION, APP_ID)
	if !tv_bus_start(APP_ID) {os.exit(1)}
	window: ^sdl.Window
	renderer: ^sdl.Renderer
	clay_memory: []u8
	defer {
		stop_playback()
		for texture in textures {if texture != nil {sdl.DestroyTexture(texture)}}
		model.catalog_destroy(&catalog)
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
	clay.SetMaxElementCount(128)
	clay.SetMaxMeasureTextCacheWordCount(512)
	clay_memory = make([]u8, int(clay.MinMemorySize()))
	clay.Initialize(
		clay.CreateArenaWithCapacityAndMemory(uint(len(clay_memory)), raw_data(clay_memory)),
		{VIEW_WIDTH, VIEW_HEIGHT},
		{handler = clay_error},
	)
	clay.SetMeasureTextFunction(measure_text, nil)
	if !sdl.SetRenderLogicalPresentation(renderer, VIEW_WIDTH, VIEW_HEIGHT, .LETTERBOX) ||
	   !sdl.SetRenderDrawBlendMode(renderer, sdl.BLENDMODE_BLEND) {return}
	path, path_error := os.get_executable_path(context.allocator)
	if path_error != nil {return}
	defer delete(path)
	app_directory = filepath.dir(path)
	if !load_catalog(renderer) {return}
	if !render(renderer) {fmt.eprintln("frame failed:", sdl.GetError()); return}
	fmt.println("video grid presented")
	start = sdl.GetTicks()
	for running && !tv_closing() && sdl.GetTicks() - start < 180000 {
		tv_poll()
		if return_to_grid {stop_playback()}
		event: sdl.Event
		if sdl.WaitEventTimeout(&event, 20) {
			#partial switch event.type {
			case .QUIT:
				running = false
			case .KEY_DOWN:
				key(input_key(event.key.raw, event.key.key))
			case .MOUSE_MOTION:
				controls_pointer(
					renderer,
					event.motion.x,
					event.motion.y,
					.LEFT in event.motion.state,
					false,
				)
			case .MOUSE_BUTTON_DOWN:
				if event.button.button == sdl.BUTTON_LEFT {
					controls_pointer(renderer, event.button.x, event.button.y, true, true)
				}
			case .MOUSE_BUTTON_UP:
				if event.button.button == sdl.BUTTON_LEFT {
					controls_pointer(renderer, event.button.x, event.button.y, false, false)
				}
			}
		}
		if !tv_visible() {running = false}
		if dirty {if !render(renderer) {break}; dirty = false}
	}
	fmt.println("player stopping")
}
