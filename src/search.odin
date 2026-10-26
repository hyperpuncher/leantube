package main

import clay "../vendor/clay"
import "core:strings"
import "core:unicode/utf8"
import sdl "vendor:sdl3"

search_editing: bool
search_replace: bool
search_text: [dynamic]u8

edit_search :: proc(window: ^sdl.Window) {
	if search_editing {return}
	clear(&search_text)
	append(&search_text, catalog.query)
	search_editing = true
	search_replace = true
	if !start_text_input(window) {
		search_editing = false
		notice = "text input is unavailable"
	}
	dirty = true
}
finish_search_input :: proc(window: ^sdl.Window) {
	search_editing = false
	rail_focus = false
	stop_text_input(window)
	dirty = true
}
append_search_text :: proc(text: string) {
	if !search_editing {return}
	length := search_replace ? 0 : len(search_text)
	if length + len(text) > 512 {return}
	if search_replace {clear(&search_text); search_replace = false}
	append(&search_text, text)
	dirty = true
}
// LG text-model deletion uses byte offsets relative to the cursor at the end.
erase_search_text :: proc(index: i32, length: u32) {
	if !search_editing {return}
	if search_replace || length == max(u32) {
		clear(&search_text)
		search_replace = false
	} else {
		start := len(search_text) + int(index)
		if start < 0 || start > len(search_text) || length > u32(len(search_text) - start) {return}
		end := start + int(length)
		if start < len(search_text) && !utf8.rune_start(search_text[start]) {return}
		if end < len(search_text) && !utf8.rune_start(search_text[end]) {return}
		copy(search_text[start:], search_text[end:])
		resize(&search_text, len(search_text) - int(length))
	}
	dirty = true
}

search_key :: proc(code: sdl.Keycode, window: ^sdl.Window) -> bool {
	if !search_editing {
		if code == sdl.K_TAB || code == sdl.K_SLASH {
			edit_search(window)
			return true
		}
		return false
	}
	switch code {
	case sdl.K_ESCAPE, sdl.K_AC_BACK, sdl.K_DOWN:
		finish_search_input(window)
	case sdl.K_RETURN, sdl.K_KP_ENTER:
		if strings.trim_space(string(search_text[:])) != "" {
			finish_search_input(window)
			start_search(string(search_text[:]))
		}
	case sdl.K_BACKSPACE:
		_, size := utf8.decode_last_rune_in_string(string(search_text[:]))
		if size > 0 {erase_search_text(-i32(size), u32(size))}
	}
	return true
}

search_layout :: proc() {
	if clay.UI(clay.ID("search-row"))(
	{
		layout = {
			sizing = {width = clay.SizingGrow({})},
			childGap = spacing(16),
			childAlignment = {y = .Center},
		},
	},
	) {
		focus := search_editing ? COLOR_ACCENT : COLOR_SURFACE
		if clay.UI(clay.ID("search"))(
		{
			layout = {
				sizing = {width = clay.SizingGrow({})},
				padding = clay.PaddingAll(spacing(4)),
			},
			backgroundColor = focus,
			cornerRadius = clay.CornerRadiusAll(scaled(8)),
		},
		) {
			if clay.UI()(
			{
				layout = {
					sizing = {width = clay.SizingGrow({})},
					padding = padding(8, 8, 4, 4),
					childGap = spacing(16),
					childAlignment = {y = .Center},
				},
				backgroundColor = COLOR_SURFACE,
				cornerRadius = clay.CornerRadiusAll(scaled(4)),
				clip = {horizontal = true, vertical = true},
			},
			) {
				value := search_editing ? string(search_text[:]) : catalog.query
				label(
					value == "" ? "Search YouTube" : value,
					.Heading,
					search_editing && search_replace ? COLOR_MUTED : COLOR_TEXT,
				)
				if clay.UI()({layout = {sizing = {width = clay.SizingGrow({})}}}) {}
				if search_loading {label("Loading…", .Caption, COLOR_MUTED)} else if notice != "" {label(notice, .Caption, COLOR_MUTED)}
			}
		}
	}
}
