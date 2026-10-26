package main

import sdl "vendor:sdl3"

input_key :: proc(raw: u16, logical: sdl.Keycode) -> sdl.Keycode {
	// LG's /usr/share/X11/xkb/keycodes/lg declares IR_KEY_BACK=420.
	// Wayland sends the keycode without XKB's offset of 8. SDL3 assigns a
	// custom scancode instead of a standard Back key on the B9.
	if raw == 420 - 8 {return sdl.K_AC_BACK}
	return logical
}
