package main

import clay "../vendor/clay"
import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import sdl "vendor:sdl3"

APP_ID :: "org.hyperpuncher.odin.tv.prototype"
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
position_ms: f64
duration_ms: f64
rate: f64 = 1
dirty := true

send :: proc(endpoint: cstring, payload: string, kind: uintptr) {
	body := strings.clone_to_cstring(payload)
	defer delete(body)
	if !tv_send(
		endpoint,
		body,
		reply,
		rawptr(kind),
	) {fmt.eprintln("request send failed; kind:", kind)}
}
command :: proc(endpoint: cstring, extra: string = "", kind: uintptr = 9) {
	if media_id == "" {return}
	body := fmt.aprintf("{{\"mediaId\":\"%s\"%s}}", media_id, extra)
	defer delete(body)
	send(endpoint, body, kind)
}
foreground :: proc() {
	body := fmt.aprintf("{{\"connectionId\":\"%s\"}}", media_id)
	defer delete(body)
	send("luna://com.webos.media/notifyForeground", body, 6)
}
reply :: proc "c" (bus, message, data: rawptr) -> bool {
	context = runtime.default_context()
	value, error := json.parse(string(tv_payload(message)))
	if error != .None {fmt.eprintln("invalid service JSON"); return true}
	defer json.destroy_value(value)
	root, ok := value.(json.Object)
	if !ok {return true}
	kind := uintptr(data)
	if success, found := root["returnValue"].(json.Boolean); found {
		fmt.printf("reply kind=%d accepted=%v\n", kind, bool(success))
		if !bool(success) {
			if code, valid := number(root["errorCode"]); valid {
				fmt.println("request error code:", code)
			}
			if kind != 1 {
				if text, has_text := root["errorText"].(json.String); has_text {
					fmt.println("control request error:", string(text))
				}
			}
			return true
		}
		if kind == 0 {registered = true}
		if kind == 11 {unloaded = true}
	}
	if kind == 0 {
		if event, found := root["event"].(json.String); found {
			fmt.println("app lifecycle:", string(event))
			if event == "close" {running = false}
			if event == "relaunch" {tv_raise()}
		}
	}
	if kind == 1 && media_id == "" {
		if id, found := root["mediaId"].(json.String); found {
			media_id = strings.clone(string(id))
			fmt.println("media session:", media_id)
			command("luna://com.webos.media/subscribe", "", 4)
			foreground()
			command("luna://com.webos.media/play")
		}
	}
	if kind == 4 {
		for name in root {
			if name != "currentTime" && name != "bufferRange" {fmt.println("media event:", name)}
		}
		if info, found := root["videoInfo"].(json.Object); found {
			width, w_ok := number(info["width"])
			height, h_ok := number(info["height"])
			fps, f_ok := number(info["frameRate"])
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
			duration_ms = source_duration(source)
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
		ms, valid := number(root["currentTime"])
		if time, found := root["currentTime"].(json.Object);
		   found {ms, valid = number(time["currentTime"])}
		if valid {
			position_ms = ms
			dirty = true
		}
		if _, found := root["error"];
		   found {fmt.eprintln("native media error event"); running = false}
		if _, found := root["endOfStream"]; found {running = false}
	}
	return true
}
key :: proc(code: sdl.Scancode) {
	fmt.println("remote scancode:", code)
	#partial switch code {
	case .ESCAPE, .AC_BACK:
		running = false
	case .RETURN, .SPACE, .KP_ENTER:
		if paused {command("luna://com.webos.media/play")} else {command("luna://com.webos.media/pause")}
	case .LEFT, .RIGHT:
		offset: f64 = -10000
		if code == .RIGHT {offset = 10000}
		extra := fmt.aprintf(",\"position\":%d", i64(max(0, position_ms + offset)))
		command("luna://com.webos.media/seek", extra)
		delete(extra)
	case .UP, .DOWN:
		delta: f64 = 0.25
		if code == .DOWN {delta = -0.25}
		rate = clamp(rate + delta, 0.5, 2)
		extra := fmt.aprintf(",\"playRate\":%.2f,\"audioOutput\":true", rate)
		command("luna://com.webos.media/setPlayRate", extra)
		delete(extra)
	}
	dirty = true
}
main :: proc() {
	_ = sdl.SetHint(sdl.HINT_VIDEO_DRIVER, "wayland")
	_ = sdl.SetAppMetadata("LeanTube", "0.0.4", APP_ID)
	if !tv_bus_start(APP_ID) {os.exit(1)}
	window: ^sdl.Window
	renderer: ^sdl.Renderer
	clay_memory: []u8
	defer {
		if media_id != "" {
			command("luna://com.webos.media/unload", "", 11)
			start := sdl.GetTicks()
			for !unloaded && sdl.GetTicks() - start < 1500 {tv_poll(); sdl.Delay(10)}
			fmt.println("media unload acknowledged:", unloaded)
			delete(media_id)
		}
		delete(video_metadata)
		if renderer != nil {sdl.DestroyRenderer(renderer)}
		tv_shutdown()
		if window != nil {sdl.DestroyWindow(window)}
		sdl.Quit()
		delete(clay_memory)
		fmt.println("native cleanup completed")
	}
	send("luna://com.webos.applicationManager/registerApp", "{\"id\":\"" + APP_ID + "\"}", 0)
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
		{CONTROL_WIDTH, CONTROL_HEIGHT},
		{handler = clay_error},
	)
	clay.SetMeasureTextFunction(measure_text, nil)
	if !sdl.SetRenderLogicalPresentation(renderer, CONTROL_WIDTH, CONTROL_HEIGHT, .LETTERBOX) ||
	   !sdl.SetRenderDrawBlendMode(renderer, sdl.BLENDMODE_BLEND) {return}
	if !render(renderer) {fmt.eprintln("frame failed:", sdl.GetError()); return}
	fmt.println("native transparent frame presented")
	path, path_error := os.get_executable_path(context.allocator)
	if path_error != nil {return}
	defer delete(path)
	load_path := fmt.aprintf("%s/load.json", filepath.dir(path))
	defer delete(load_path)
	load, load_error := os.read_entire_file(load_path, context.allocator)
	if load_error != nil {fmt.eprintln("stream request file missing"); return}
	defer delete(load)
	send("luna://com.webos.media/load", string(load), 1)
	start = sdl.GetTicks()
	for running && !tv_closing() && sdl.GetTicks() - start < 180000 {
		tv_poll()
		event: sdl.Event
		if sdl.WaitEventTimeout(&event, 20) {
			#partial switch event.type {
			case .QUIT:
				running = false
			case .KEY_DOWN:
				key(event.key.scancode)
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
