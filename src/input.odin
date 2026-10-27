package main

import sdl "vendor:sdl3"

input_key :: proc(raw: u16, logical: sdl.Keycode) -> sdl.Keycode {
	// LG's /usr/share/X11/xkb/keycodes/lg declares IR_KEY_BACK=420.
	// Wayland sends the keycode without XKB's offset of 8. SDL3 assigns a
	// custom scancode instead of a standard Back key on the B9.
	switch raw {
	case 420 - 8:
		return sdl.K_AC_BACK
	// The remote sends play and pause as separate keys, with no state.
	case 215 - 8:
		return sdl.K_MEDIA_PLAY
	case 127 - 8:
		return sdl.K_MEDIA_PAUSE
	}
	return logical
}
