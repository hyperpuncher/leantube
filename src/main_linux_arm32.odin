package main

import clay "../vendor/clay"
import "base:runtime"
import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:sys/posix"
import sdl "vendor:sdl3"

APP_ID :: #config(APP_ID, "org.hyperpuncher.leantube")
APP_VERSION :: #config(APP_VERSION, "dev")
WEBOS_LEGACY :: #config(WEBOS_LEGACY, false)
when WEBOS_LEGACY {
	APP_TEMP_PREFIX :: "/tmp/leantube-legacy"
} else {
	APP_TEMP_PREFIX :: "/tmp/leantube"
}
foreign import bridge "system:tv_bridge"
foreign bridge {
	tv_clay_abi :: proc(command_size, config_size, error_size: u32) -> bool ---
}
registered: bool
interrupted: i32
stop_signal :: proc "c" (_: posix.Signal) {sync.atomic_store(&interrupted, 1)}

register_application :: proc() -> bool {
	error: LS_Error
	LSErrorInit(&error)
	defer LSErrorFree(&error)
	token: c.ulong
	endpoint: cstring = "luna://com.webos.applicationManager/registerApp"
	when WEBOS_LEGACY {endpoint = "luna://com.webos.applicationManager/registerNativeApp"}
	payload: cstring = "{\"id\":\"" + APP_ID + "\"}"
	when WEBOS_LEGACY {payload = "{\"id\":\"" + APP_ID + "\",\"subscribe\":true}"}
	return LSCall(bus, endpoint, payload, reply, nil, &token, &error)
}

reply :: proc "c" (_: rawptr, message: rawptr, _: rawptr) -> bool {
	context = runtime.default_context()
	value, error := json.parse(string(LSMessageGetPayload(message)))
	if error != .None {return true}
	defer json.destroy_value(value)
	root, ok := value.(json.Object)
	if !ok {return true}
	if success, found := root["returnValue"].(json.Boolean); found {
		if !bool(success) {return true}
		registered = true
	}
	switch lifecycle_event(root, WEBOS_LEGACY) {
	case "close":
		running = false
	case "relaunch":
		raise_window()
		queue_control(launch_parameters(root))
	}
	return true
}

main :: proc() {
	when WEBOS_LEGACY {_ = sdl.SetHint("SDL_WEBOS_LEGACY_SEAT", "1")}
	benchmark_reader_entry()
	_ = sdl.SetHint(sdl.HINT_VIDEO_DRIVER, "wayland")
	_ = sdl.SetAppMetadata("LeanTube", APP_VERSION, APP_ID)
	setup_logging()
	_ = os.remove(CONTROL_STATE)
	if len(os.args) > 1 {
		if value, err := json.parse(os.args[1]); err == .None {
			if root, ok := value.(json.Object); ok {queue_control(launch_parameters(root))}
			json.destroy_value(value)
		}
	}
	action := posix.sigaction_t {
		sa_handler = stop_signal,
	}
	if posix.sigaction(.SIGTERM, &action, nil) != .OK ||
	   posix.sigaction(.SIGINT, &action, nil) != .OK {return}
	if !start_bus(APP_ID) {os.exit(1)}
	window: ^sdl.Window
	renderer: ^sdl.Renderer
	clay_memory: []u8
	defer {
		if search_editing {finish_search_input(window)}
		stop_playback()
		write_control_state(true)
		close_login_screen()
		stop_network()
		delete(search_text)
		clear_browse_history()
		delete(browse_id); delete(browse_params); delete(browse_filter)
		clear_catalog()
		close_fade()
		close_icons()
		close_tv_cursor()
		close_text()
		if renderer != nil {sdl.DestroyRenderer(renderer)}
		close_window()
		close_bus()
		if window != nil {sdl.DestroyWindow(window)}
		sdl.Quit()
		delete(clay_memory)
		fmt.println("native cleanup completed")
	}
	path, path_error := os.get_executable_path(context.allocator)
	if path_error != nil {return}
	defer delete(path)
	app_directory = filepath.dir(path)
	// Use the firmware's EGL adapter, never a copied driver-specific binary.
	legacy_egl := "/usr/lib/libwayland-egl.so.0"
	egl_alias := fmt.aprintf("%s/lib/libwayland-egl.so.1", app_directory)
	defer delete(egl_alias)
	if os.exists(legacy_egl) && !os.exists(egl_alias) {
		if error := os.symlink(legacy_egl, egl_alias); error != nil {
			fmt.eprintln("EGL adapter alias failed:", error)
			return
		}
	}
	if !register_application() {return}
	start := sdl.GetTicks()
	for !registered && sdl.GetTicks() - start < 3000 {poll_services(); sdl.Delay(10)}
	if !registered {fmt.eprintln("registration failed"); return}
	if !sdl.Init({.VIDEO}) {fmt.eprintln("SDL init failed:", sdl.GetError()); return}
	window = create_window()
	if window == nil {fmt.eprintln("window failed:", sdl.GetError()); return}
	properties := sdl.GetWindowProperties(window)
	if !attach_window(
		APP_ID,
		sdl.GetPointerProperty(properties, sdl.PROP_WINDOW_WAYLAND_DISPLAY_POINTER, nil),
		sdl.GetPointerProperty(properties, sdl.PROP_WINDOW_WAYLAND_SURFACE_POINTER, nil),
	) {fmt.eprintln("LG window role is unavailable"); return}
	renderer = sdl.CreateRenderer(window, "opengles2")
	if renderer == nil {fmt.eprintln("renderer failed:", sdl.GetError()); return}
	// Present on the panel's refresh so a frame is never shown half updated.
	if !sdl.SetRenderVSync(renderer, 1) {fmt.eprintln("vsync is unavailable:", sdl.GetError())}
	if !tv_clay_abi(
		u32(size_of(clay.RenderCommand)),
		u32(size_of(clay.ElementDeclaration)),
		u32(size_of(clay.ErrorData)),
	) {fmt.eprintln("Clay ABI mismatch"); return}
	clay.SetMaxElementCount(8192)
	clay.SetMaxMeasureTextCacheWordCount(32768)
	clay_memory = make([]u8, int(clay.MinMemorySize()))
	clay.Initialize(
		clay.CreateArenaWithCapacityAndMemory(uint(len(clay_memory)), raw_data(clay_memory)),
		{},
		{handler = clay_error},
	)
	clay.SetMeasureTextFunction(measure_text, nil)
	if !sdl.SetRenderDrawBlendMode(renderer, sdl.BLENDMODE_BLEND) {return}
	if !open_tv_cursor() {fmt.eprintln("cursor failed:", sdl.GetError())}
	if !open_text(renderer) {fmt.eprintln("UI assets failed:", sdl.GetError()); return}
	init_player()
	if start_network() {
		if pending_control.action == .Open {apply_control(window)} else {
			activate_navigation(signed_in ? .Subscriptions : .Home)
		}
	} else {
		notice = "network is unavailable"
	}
	if !render(renderer) {fmt.eprintln("frame failed:", sdl.GetError()); return}
	fmt.println("video grid presented")
	previous_frame := sdl.GetTicks()
	for running && !window_closing && sync.atomic_load(&interrupted) == 0 {
		poll_services()
		if return_to_grid {stop_playback()}
		apply_control(window)
		wheel: f32
		event: sdl.Event
		if sdl.WaitEventTimeout(&event, loading_active() ? 0 : 20) {
			// SDL documents draining the queue after the blocking wait.
			for {
				wheel += handle_event(renderer, event)
				if !sdl.PollEvent(&event) {break}
			}
		}
		poll_network(renderer)
		poll_player()
		poll_card_press(sdl.GetTicks())
		poll_login_tick()
		auto_skip_sponsor()
		write_control_state()
		expire_player_controls()
		now := sdl.GetTicks()
		frame_dt := f32(min(now - previous_frame, 50)) / 1000
		previous_frame = now
		if !window_visible {running = false}
		if dirty || loading_active() {if !render(renderer, wheel, frame_dt) {break}; dirty = false}
	}
	fmt.println("player stopping")
}
