package main

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:strings"
import "core:sync"

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
foreign import acb "system:AcbAPI"
foreign acb {
	AcbAPI_create :: proc() -> c.long ---
	AcbAPI_initialize :: proc(id: c.long, player_type: c.int, app_id: cstring, callback: Acb_Callback) -> bool ---
	AcbAPI_setMediaId :: proc(id: c.long, media_id: cstring) -> bool ---
	// The B9 ABI includes the task output pointer omitted by the SDK header.
	AcbAPI_setMediaVideoData :: proc(id: c.long, payload: cstring, task: ^c.long) -> c.int ---
	AcbAPI_setState :: proc(id: c.long, app_state: Acb_App_State, play_state: Acb_Play_State, task: ^c.long) -> c.int ---
	AcbAPI_setDisplayWindow :: proc(id, x, y, width, height: c.long, fullscreen: bool, task: ^c.long) -> c.int ---
	AcbAPI_finalize :: proc(id: c.long) -> c.int ---
	AcbAPI_destroy :: proc(id: c.long) ---
}

acb_id: c.long = -1
display_ready: i32
pending_video_data: cstring

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

update_display :: proc(video_data: string) {
	delete(pending_video_data)
	pending_video_data = strings.clone_to_cstring(video_data)
}

attach_display :: proc(app_id: cstring, media_id, video_data: string) -> bool {
	update_display(video_data)
	acb_id = AcbAPI_create()
	fmt.eprintln("display control created id:", acb_id)
	if acb_id < 0 || !AcbAPI_initialize(acb_id, 0, app_id, display_event) {
		fmt.eprintln("display control initialization failed")
		return false
	}
	id := strings.clone_to_cstring(media_id)
	defer delete(id)
	bound := AcbAPI_setMediaId(acb_id, id)
	task: c.long
	loaded := AcbAPI_setState(acb_id, .Foreground, .Loaded, &task)
	window := AcbAPI_setDisplayWindow(acb_id, 0, 0, 1920, 1080, true, &task)
	fmt.eprintf("display bind=%v loaded=%d window=%d\n", bound, loaded, window)
	return bound
}

poll_display :: proc() {
	// ACB signals readiness on its worker. Run its API only on the main thread.
	if pending_video_data == nil || acb_id < 0 || sync.atomic_load(&display_ready) == 0 {return}
	task: c.long
	metadata := AcbAPI_setMediaVideoData(acb_id, pending_video_data, &task)
	fmt.eprintf("display metadata accepted=%d task=%d\n", metadata, task)
	delete(pending_video_data); pending_video_data = nil
	playing := AcbAPI_setState(acb_id, .Foreground, .Playing, &task)
	fmt.eprintf("display playing accepted=%d task=%d\n", playing, task)
}

release_display :: proc() {
	delete(pending_video_data); pending_video_data = nil
	if acb_id >= 0 {
		task: c.long
		AcbAPI_setState(acb_id, .Background, .Unloaded, &task)
		AcbAPI_finalize(acb_id)
		AcbAPI_destroy(acb_id)
		acb_id = -1
	}
	sync.atomic_store(&display_ready, 0)
}
