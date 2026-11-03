package main

import "./model"
import yt "./youtube"
import "core:encoding/json"
import "core:math"
import "core:strings"
import sdl "vendor:sdl3"

Control_Action :: enum {
	None,
	Open,
	Seek,
	Pause,
	Resume,
}
Control_Command :: struct {
	action:      Control_Action,
	video_id:    [11]u8,
	position_ms: f64,
	paused:      bool,
}
pending_control: Control_Command
control_error: string
control_started_at: u64

parse_control :: proc(value: json.Value) -> (command: Control_Command, valid: bool) {
	object, ok := value.(json.Object)
	if !ok {return}
	action, _ := object["action"].(json.String)
	switch action {
	case "open":
		command.action = .Open
	case "seek":
		command.action = .Seek
	case "pause":
		command.action = .Pause
	case "resume":
		command.action = .Resume
	case:
		return
	}
	if command.action == .Open {
		id, _ := object["videoId"].(json.String)
		if !yt.video_id_valid(string(id)) {return {}, false}
		copy(command.video_id[:], string(id))
	}
	if position, supplied := object["position"]; supplied {
		seconds, number := model.number(position)
		if !number ||
		   seconds < 0 ||
		   math.is_nan(seconds) ||
		   math.is_inf(seconds * 1000) {return {}, false}
		command.position_ms = seconds * 1000
	} else if command.action == .Seek {return {}, false}
	if paused, supplied := object["paused"]; supplied {
		flag, boolean := paused.(json.Boolean)
		if !boolean {return {}, false}
		command.paused = bool(flag)
	}
	return command, true
}

queue_control :: proc(value: json.Value) {
	if command, valid := parse_control(value); valid {pending_control = command}
}

// Apply lifecycle commands on the main loop, never inside a Luna callback.
apply_control :: proc(window: ^sdl.Window = nil) {
	command := pending_control
	if command.action == .None {return}
	pending_control = {}
	control_error = ""
	control_started_at = sdl.GetTicks()
	switch command.action {
	case .Open:
		if search_editing {finish_search_input(window)}
		close_login_screen()
		account_menu = false
		stop_playback()
		clear_catalog()
		id := string(command.video_id[:])
		append(&catalog.videos, model.Video{id = strings.clone(id), title = strings.clone(id)})
		resize(&textures, 1)
		resize(&card_avatars, 1)
		selected = 0
		resolve_selected(command.position_ms, command.paused)
	case .Seek:
		if !seek_to(command.position_ms) {control_error = "seek unavailable"}
	case .Pause:
		if !player_pause(true) {control_error = "pause unavailable"}
	case .Resume:
		if !player_pause(false) {control_error = "resume unavailable"}
	case .None:
	}
	dirty = true
}
