/*
  Based on SDL-webOS, contributed by Mariotaku <mariotaku.lee@gmail.com>.
  Modified for LeanTube: use public Wayland APIs and Odin input callbacks.

  Simple DirectMedia Layer
  Copyright (C) 1997-2023 Sam Lantinga <slouken@libsdl.org>

  This software is provided 'as-is', without any express or implied
  warranty. In no event will the authors be held liable for any damages
  arising from the use of this software.

  Permission is granted to anyone to use this software for any purpose,
  including commercial applications, and to alter it and redistribute it
  freely, subject to the following restrictions:

  1. The origin of this software must not be misrepresented; you must not
	 claim that you wrote the original software. If you use this software
	 in a product, an acknowledgment in the product documentation would be
	 appreciated but is not required.
  2. Altered source versions must be plainly marked as such, and must not be
	 misrepresented as being the original software.
  3. This notice may not be removed or altered from any source distribution.
*/
package main

import "base:runtime"
import "core:strings"
import sdl "vendor:sdl3"

WL_Text_Listener :: struct {
	commit_string:           proc "c" (data, model: rawptr, serial: u32, text: cstring),
	preedit_string:          proc "c" (data, model: rawptr, serial: u32, text, commit: cstring),
	delete_surrounding_text: proc "c" (data, model: rawptr, serial: u32, index: i32, length: u32),
	cursor_position:         proc "c" (data, model: rawptr, serial: u32, index, anchor: i32),
	preedit_styling:         proc "c" (data, model: rawptr, serial, index, length, style: u32),
	preedit_cursor:          proc "c" (data, model: rawptr, serial: u32, index: i32),
	modifiers_map:           proc "c" (data, model, modifiers: rawptr),
	keysym:                  proc "c" (data, model: rawptr, serial, time, sym, state, mods: u32),
	enter:                   proc "c" (data, model, surface: rawptr),
	leave:                   proc "c" (data, model: rawptr),
	input_panel_state:       proc "c" (data, model: rawptr, state: u32),
	input_panel_rect:        proc "c" (data, model: rawptr, x, y: i32, width, height: u32),
}

keyboard_factory, keyboard_seat, keyboard_model: rawptr
keyboard_serial: u32
keyboard_active: bool
text_input_window: ^sdl.Window
seat_listener := WL_Seat_Listener{seat_capabilities, seat_name}
text_listener := WL_Text_Listener {
	keyboard_commit,
	keyboard_preedit,
	keyboard_erase,
	keyboard_cursor,
	keyboard_styling,
	keyboard_preedit_cursor,
	keyboard_modifiers,
	keyboard_keysym,
	keyboard_enter,
	keyboard_leave,
	keyboard_panel_state,
	keyboard_panel_rect,
}

start_text_input :: proc(window: ^sdl.Window) -> bool {
	if window == nil {return true}
	if keyboard_factory == nil || keyboard_seat == nil || window_surface == nil {return false}
	if !sdl.StartTextInput(window) {return false}
	if keyboard_model == nil {
		keyboard_model = text_model_factory_create_text_model(keyboard_factory)
		if keyboard_model == nil {_ = sdl.StopTextInput(window); return false}
		wl_proxy_add_listener(keyboard_model, &text_listener, nil)
	}
	text_input_window = window
	keyboard_active = true
	keyboard_serial += 1
	text_model_activate(keyboard_model, keyboard_serial, keyboard_seat, window_surface)
	text_model_set_content_type(keyboard_model, 0, 0) // No hints; normal text.
	text_model_set_enter_key_type(keyboard_model, 5) // Search.
	text_model_set_max_text_length(keyboard_model, 512)
	update_text_input()
	return true
}
update_text_input :: proc() {
	if !keyboard_active {return}
	text, err := strings.to_cstring(&search_text)
	if err != nil {return}
	text_model_set_surrounding_text(
		keyboard_model,
		text,
		u32(search_editor.selection[0]),
		u32(search_editor.selection[1]),
	)
	wl_display_flush(window_display)
}
stop_text_input :: proc(window: ^sdl.Window) {
	hide_keyboard()
	if window != nil {_ = sdl.StopTextInput(window)}
	text_input_window = nil
}
hide_keyboard :: proc() {
	if keyboard_model == nil {return}
	if keyboard_active {text_model_deactivate(keyboard_model, keyboard_seat)}
	keyboard_active = false
	wl_proxy_destroy(keyboard_model)
	keyboard_model = nil
	wl_display_flush(window_display)
}
close_keyboard :: proc() {
	hide_keyboard()
	if keyboard_factory != nil {wl_proxy_destroy(keyboard_factory)}
	if keyboard_seat != nil {wl_proxy_destroy(keyboard_seat)}
	keyboard_factory, keyboard_seat = nil, nil
}

keyboard_commit :: proc "c" (data, model: rawptr, serial: u32, text: cstring) {
	context = runtime.default_context()
	if keyboard_active {append_search_text(string(text))}
}
keyboard_erase :: proc "c" (data, model: rawptr, serial: u32, index: i32, length: u32) {
	context = runtime.default_context()
	if keyboard_active {erase_search_text(index, length)}
}
keyboard_keysym :: proc "c" (data, model: rawptr, serial, time, sym, state, mods: u32) {
	context = runtime.default_context()
	if !keyboard_active || state != 1 {return} 	// Pressed.
	switch sym {
	case 0xff0d:
		search_key(sdl.K_RETURN, text_input_window)
	case 0xff08:
		search_key(sdl.K_BACKSPACE, text_input_window)
	case 0xffff:
		search_key(sdl.K_DELETE, text_input_window)
	case 0xff51:
		search_key(sdl.K_LEFT, text_input_window)
	case 0xff53:
		search_key(sdl.K_RIGHT, text_input_window)
	case 0xff50:
		search_key(sdl.K_HOME, text_input_window)
	case 0xff57:
		search_key(sdl.K_END, text_input_window)
	case 0xff1b:
		search_key(sdl.K_ESCAPE, text_input_window)
	}
}
keyboard_leave :: proc "c" (data, model: rawptr) {
	context = runtime.default_context()
	if model != keyboard_model {return}
	was_active := keyboard_active
	keyboard_active = false
	wl_proxy_destroy(model)
	keyboard_model = nil
	if was_active && search_editing {finish_search_input(text_input_window)}
}
keyboard_panel_state :: proc "c" (data, model: rawptr, state: u32) {
	context = runtime.default_context()
	if state == 0 && keyboard_active && model == keyboard_model {
		hide_keyboard()
		if search_editing {finish_search_input(text_input_window)}
	}
}

// The protocol requires a listener entry for every event, including unused ones.
keyboard_preedit :: proc "c" (data, model: rawptr, serial: u32, text, commit: cstring) {}
keyboard_cursor :: proc "c" (data, model: rawptr, serial: u32, index, anchor: i32) {}
keyboard_styling :: proc "c" (data, model: rawptr, serial, index, length, style: u32) {}
keyboard_preedit_cursor :: proc "c" (data, model: rawptr, serial: u32, index: i32) {}
keyboard_modifiers :: proc "c" (data, model, modifiers: rawptr) {}
keyboard_enter :: proc "c" (data, model, surface: rawptr) {}
keyboard_panel_rect :: proc "c" (data, model: rawptr, x, y: i32, width, height: u32) {}
seat_capabilities :: proc "c" (data, seat: rawptr, caps: u32) {}
seat_name :: proc "c" (data, seat: rawptr, name: cstring) {}
