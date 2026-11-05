package main

import "base:runtime"
import "core:c"
import "core:dynlib"
import "core:fmt"
import "core:strings"
import "core:sync"
import sdl "vendor:sdl3"

Acb_App_State :: enum c.int {
	Initialized,
	Foreground,
	Background,
}
Acb_Play_State :: enum c.int {
	Unloaded,
	Loaded,
	Playing,
	Paused,
}
Acb_Callback :: #type proc "c" (id, task, event, app_state, play_state: c.long, reply: cstring)

// libAcbAPI is only present below webOS 5, so resolve it at runtime.
Acb :: struct {
	__handle:                 dynlib.Library,
	AcbAPI_create:            proc() -> c.long,
	AcbAPI_initialize:        proc(
		id: c.long,
		player_type: c.int,
		app_id: cstring,
		callback: Acb_Callback,
	) -> bool,
	AcbAPI_setMediaId:        proc(id: c.long, media_id: cstring) -> bool,
	AcbAPI_setSinkType:       proc(id: c.long, sink_type: c.int) -> bool,
	AcbAPI_setMediaVideoData: proc(id: c.long, payload: cstring, task: ^c.long) -> c.int,
	AcbAPI_setState:          proc(
		id: c.long,
		app_state: Acb_App_State,
		play_state: Acb_Play_State,
		task: ^c.long,
	) -> c.int,
	AcbAPI_setDisplayWindow:  proc(
		id, x, y, width, height: c.long,
		fullscreen: bool,
		task: ^c.long,
	) -> c.int,
	AcbAPI_finalize:          proc(id: c.long) -> c.int,
	AcbAPI_destroy:           proc(id: c.long),
}
ACB_SYMBOLS :: 9

foreign import bridge "system:tv_bridge"
foreign bridge {
	lt_export_window :: proc(display, surface: rawptr) -> bool ---
	lt_window_id :: proc() -> cstring ---
	lt_set_window :: proc(source_width, source_height, destination_width, destination_height: c.int) -> bool ---
	lt_unexport_window :: proc() ---
}

acb: Acb
Acb_State :: enum {
	Unknown,
	Loaded,
	Missing,
}
acb_state: Acb_State
acb_id: c.long = -1
foreign_window: bool
display_ready: i32
pending_video_data: cstring
display_width, display_height: c.int
destination_width, destination_height: c.int = 1920, 1080

display_event :: proc "c" (id, task, event, app_state, play_state: c.long, reply: cstring) {
	context = runtime.default_context()
	fmt.eprintf(
		"display event id=%d task=%d event=%d app=%d play=%d\n",
		id,
		task,
		event,
		app_state,
		play_state,
	)
	if event == 1 &&
	   app_state == c.long(Acb_App_State.Foreground) &&
	   play_state == c.long(Acb_Play_State.Loaded) {
		sync.atomic_store(&display_ready, 1)
	}
}

load_acb :: proc() -> bool {
	#partial switch acb_state {
	case .Loaded:
		return true
	case .Missing:
		return false
	}
	count, ok := dynlib.initialize_symbols(&acb, "libAcbAPI.so.1")
	if !ok || count != ACB_SYMBOLS {
		acb_state = .Missing
		fmt.eprintln("display: libAcbAPI unavailable")
		return false
	}
	acb_state = .Loaded
	return true
}

update_display :: proc(video_data: string) {
	delete(pending_video_data)
	pending_video_data = strings.clone_to_cstring(video_data)
}

attach_display :: proc(
	app_id: cstring,
	media_id, video_data: string,
	width, height: c.int,
) -> bool {
	update_display(video_data)
	display_width, display_height = width, height
	if bounds: sdl.Rect; sdl.GetDisplayBounds(sdl.GetPrimaryDisplay(), &bounds) {
		destination_width, destination_height = bounds.w, bounds.h
	}
	if load_acb() {
		acb_id = acb.AcbAPI_create()
		fmt.eprintln("display control created id:", acb_id)
		// Player type 10 is the MSE pipeline used by the native app.
		if acb_id < 0 || !acb.AcbAPI_initialize(acb_id, 10, app_id, display_event) {
			fmt.eprintln("display control initialization failed")
			return false
		}
		id := strings.clone_to_cstring(media_id)
		defer delete(id)
		bound := acb.AcbAPI_setMediaId(acb_id, id)
		task: c.long
		window := acb.AcbAPI_setDisplayWindow(
			acb_id,
			0,
			0,
			c.long(destination_width),
			c.long(destination_height),
			true,
			&task,
		)
		fmt.eprintf("display bind=%v window=%d\n", bound, window)
		return bound
	}
	foreign_window = lt_export_window(window_display, window_surface)
	if foreign_window {
		fmt.eprintln("display: exported window ready")
	} else {
		fmt.eprintln("display: no video plane backend available")
	}
	return foreign_window
}

// The native pipeline needs the window id while loading on webOS 5 and later.
display_window_id :: proc() -> string {
	return foreign_window ? string(lt_window_id()) : ""
}

// Called once the decoder reports its first load, for either backend.
display_started :: proc() -> bool {
	if foreign_window {
		return lt_set_window(display_width, display_height, destination_width, destination_height)
	}
	if acb_id < 0 {return false}
	task: c.long
	sink := acb.AcbAPI_setSinkType(acb_id, 0)
	state := acb.AcbAPI_setState(acb_id, .Foreground, .Loaded, &task)
	fmt.eprintf("display sink=%v state=%d\n", sink, state)
	// The main sink request can return false when the default sink is
	// already in use. The loaded state is the required transition.
	return state >= 0
}

poll_display :: proc() {
	// ACB signals readiness on its worker. Run its API only on the main thread.
	if pending_video_data == nil || acb_id < 0 || sync.atomic_load(&display_ready) == 0 {return}
	task: c.long
	metadata := acb.AcbAPI_setMediaVideoData(acb_id, pending_video_data, &task)
	fmt.eprintf("display metadata accepted=%d task=%d\n", metadata, task)
	delete(pending_video_data); pending_video_data = nil
	playing := acb.AcbAPI_setState(acb_id, .Foreground, .Playing, &task)
	fmt.eprintf("display playing accepted=%d task=%d\n", playing, task)
}

release_display :: proc() {
	delete(pending_video_data); pending_video_data = nil
	if acb_id >= 0 {
		task: c.long
		acb.AcbAPI_setState(acb_id, .Background, .Unloaded, &task)
		acb.AcbAPI_finalize(acb_id)
		acb.AcbAPI_destroy(acb_id)
		acb_id = -1
	}
	if foreign_window {
		lt_unexport_window()
		foreign_window = false
	}
	sync.atomic_store(&display_ready, 0)
}
