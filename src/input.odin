package main

import "core:testing"
import sdl "vendor:sdl3"

input_key :: proc(raw: u16, logical: sdl.Keycode) -> sdl.Keycode {
	// LG's /usr/share/X11/xkb/keycodes/lg declares IR_KEY_BACK=420.
	// Wayland sends the keycode without XKB's offset of 8. SDL3 assigns a
	// custom scancode instead of a standard Back key on the B9.
	if raw == 420 - 8 {return sdl.K_AC_BACK}
	return logical
}

@(test)
remote_back_uses_the_same_action_as_standard_back :: proc(t: ^testing.T) {
	testing.expect_value(t, input_key(412, sdl.K_UNKNOWN), sdl.Keycode(sdl.K_AC_BACK))
	testing.expect_value(t, input_key(412, sdl.Keycode(0x200003)), sdl.Keycode(sdl.K_AC_BACK))
}

@(test)
ordinary_keys_keep_their_logical_meaning :: proc(t: ^testing.T) {
	testing.expect_value(t, input_key(28, sdl.K_RETURN), sdl.Keycode(sdl.K_RETURN))
	testing.expect_value(t, input_key(105, sdl.K_LEFT), sdl.Keycode(sdl.K_LEFT))
	testing.expect_value(t, input_key(773, sdl.K_UNKNOWN), sdl.Keycode(sdl.K_UNKNOWN))
}
