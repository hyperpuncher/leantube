package main

import "core:c"

// The generated Wayland helpers, the Clay ABI check, and the exported-window
// calls all live in the app-private tv_bridge library.
foreign import bridge "system:tv_bridge"
foreign bridge {
	tv_clay_abi :: proc(command_size, config_size, error_size: u32) -> bool ---
	lt_export_window :: proc(display, surface: rawptr) -> bool ---
	lt_window_id :: proc() -> cstring ---
	lt_set_window :: proc(source_width, source_height, destination_width, destination_height: c.int) -> bool ---
	lt_unexport_window :: proc() ---
}
@(link_prefix = "lt_")
foreign bridge {
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
foreign bridge {
	wl_webos_shell_interface, text_model_factory_interface: WL_Interface
}
