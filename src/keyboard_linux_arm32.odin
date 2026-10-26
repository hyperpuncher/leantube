package main

import "base:runtime"
import sdl "vendor:sdl3"

Text_Callback :: #type proc "c" (event: u32, text: cstring, index: i32, length: u32)
foreign import keyboard "system:tv_bridge"
foreign keyboard {
	tv_keyboard_show :: proc(callback: Text_Callback) -> bool ---
	tv_keyboard_hide :: proc() ---
}
text_input_window: ^sdl.Window

start_text_input :: proc(window: ^sdl.Window) -> bool {
	if window == nil {return true}
	if !sdl.StartTextInput(window) {return false}
	text_input_window = window
	if !tv_keyboard_show(text_input_event) {
		_ = sdl.StopTextInput(window)
		text_input_window = nil
		return false
	}
	return true
}
stop_text_input :: proc(window: ^sdl.Window) {
	tv_keyboard_hide()
	if window != nil {_ = sdl.StopTextInput(window)}
	text_input_window = nil
}
text_input_event :: proc "c" (event: u32, text: cstring, index: i32, length: u32) {
	context = runtime.default_context()
	switch event {
	case 1:
		append_search_text(string(text))
	case 2:
		switch index {
		case 0xff0d:
			search_key(sdl.K_RETURN, text_input_window)
		case 0xff08:
			search_key(sdl.K_BACKSPACE, text_input_window)
		case 0xff1b:
			search_key(sdl.K_ESCAPE, text_input_window)
		}
	case 3:
		erase_search_text(index, length)
	case 4:
		if search_editing {finish_search_input(text_input_window)}
	}
}
