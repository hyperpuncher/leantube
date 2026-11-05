package main

import "core:c"

WL_Interface :: struct {
	name:                  cstring,
	version, method_count: c.int,
	methods:               rawptr,
	event_count:           c.int,
	events:                rawptr,
}
WL_Registry_Listener :: struct {
	global:        proc "c" (data, registry: rawptr, name: u32, interface: cstring, version: u32),
	global_remove: proc "c" (data, registry: rawptr, name: u32),
}
WL_Shell_Listener :: struct {
	ping:       proc "c" (data, surface: rawptr, serial: u32),
	configure:  proc "c" (data, surface: rawptr, edges: u32, width, height: i32),
	popup_done: proc "c" (data, surface: rawptr),
}
WL_Webos_Listener :: struct {
	state_changed:         proc "c" (data, surface: rawptr, state: u32),
	position_changed:      proc "c" (data, surface: rawptr, x, y: i32),
	close:                 proc "c" (data, surface: rawptr),
	exposed:               proc "c" (data, surface, rectangles: rawptr),
	state_about_to_change: proc "c" (data, surface: rawptr, state: u32),
}
WL_Seat_Listener :: struct {
	capabilities: proc "c" (data, seat: rawptr, caps: u32),
	name:         proc "c" (data, seat: rawptr, name: cstring),
}

foreign import wayland "system:wayland-client"
foreign wayland {
	wl_display_roundtrip :: proc(display: rawptr) -> c.int ---
	wl_display_flush :: proc(display: rawptr) -> c.int ---
	wl_proxy_add_listener :: proc(proxy, listener, data: rawptr) -> c.int ---
	wl_proxy_destroy :: proc(proxy: rawptr) ---
	wl_shell_interface, wl_seat_interface: WL_Interface
}
