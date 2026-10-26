#+test
package main

import "core:testing"
import sdl "vendor:sdl3"

@(test)
remote_back_uses_the_same_action_as_standard_back :: proc(t: ^testing.T) {
	testing.expect_value(t, input_key(412, sdl.K_UNKNOWN), sdl.Keycode(sdl.K_AC_BACK))
	testing.expect_value(t, input_key(412, sdl.Keycode(0x200003)), sdl.Keycode(sdl.K_AC_BACK))
}
