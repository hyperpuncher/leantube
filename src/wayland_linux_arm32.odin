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
foreign import protocol "system:tv_bridge"
@(link_prefix = "lt_")
foreign protocol {
	wl_display_get_registry :: proc(display: rawptr) -> rawptr ---
	wl_registry_bind :: proc(registry: rawptr, name: u32, interface: ^WL_Interface, version: u32) -> rawptr ---
	wl_shell_get_shell_surface :: proc(shell, surface: rawptr) -> rawptr ---
	wl_shell_surface_pong :: proc(surface: rawptr, serial: u32) ---
	wl_shell_surface_set_class :: proc(surface: rawptr, name: cstring) ---
	wl_shell_surface_set_toplevel :: proc(surface: rawptr) ---
	wl_webos_shell_get_shell_surface :: proc(shell, surface: rawptr) -> rawptr ---
	wl_webos_shell_surface_set_property :: proc(surface: rawptr, name, value: cstring) ---
	wl_webos_shell_surface_set_state :: proc(surface: rawptr, state: u32) ---
	text_model_factory_create_text_model :: proc(factory: rawptr) -> rawptr ---
	text_model_activate :: proc(model: rawptr, serial: u32, seat, surface: rawptr) ---
	text_model_deactivate :: proc(model, seat: rawptr) ---
	text_model_set_content_type :: proc(model: rawptr, hint, purpose: u32) ---
	text_model_set_enter_key_type :: proc(model: rawptr, kind: u32) ---
	text_model_set_max_text_length :: proc(model: rawptr, length: u32) ---
	text_model_set_surrounding_text :: proc(model: rawptr, text: cstring, cursor, anchor: u32) ---
}
foreign protocol {
	wl_webos_shell_interface, text_model_factory_interface: WL_Interface
}
