#+test
package main

import "core:testing"
import sdl "vendor:sdl3"

@(test)
remote_back_uses_the_same_action_as_standard_back :: proc(t: ^testing.T) {
	testing.expect_value(t, input_key(412, sdl.K_UNKNOWN), sdl.Keycode(sdl.K_AC_BACK))
	testing.expect_value(t, input_key(412, sdl.Keycode(0x200003)), sdl.Keycode(sdl.K_AC_BACK))
	// A held back key must not dismiss successive screens through repeats.
	saved_menu := account_menu
	defer {account_menu = saved_menu}
	account_menu = true
	event: sdl.Event
	event.type = .KEY_DOWN
	event.key.raw = 412
	event.key.repeat = true
	handle_event(nil, event)
	testing.expect(t, account_menu)
}

@(test)
remote_play_and_pause_keep_their_own_keys :: proc(t: ^testing.T) {
	testing.expect_value(t, input_key(207, sdl.K_UNKNOWN), sdl.Keycode(sdl.K_MEDIA_PLAY))
	testing.expect_value(t, input_key(119, sdl.K_UNKNOWN), sdl.Keycode(sdl.K_MEDIA_PAUSE))
}
