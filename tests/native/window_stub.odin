package main

import "core:c"

// The display test replaces the TV window and video plane, so these stay inert.
window_display, window_surface: rawptr

lt_export_window :: proc(_: rawptr, _: rawptr) -> bool {return false}
lt_window_id :: proc() -> cstring {return nil}
lt_set_window :: proc(_: c.int, _: c.int, _: c.int, _: c.int) -> bool {return false}
lt_unexport_window :: proc() {}
LSMessageGetPayload :: proc(_: rawptr) -> cstring {return nil}
bus_call :: proc(
	_: cstring,
	_: cstring,
	_: proc "c" (_: rawptr, _: rawptr, _: rawptr) -> bool = nil,
) -> bool {return true}
