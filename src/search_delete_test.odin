#+test
package main

import "core:strings"
import "core:testing"
import sdl "vendor:sdl3"

@(test)
ime_deletion_preserves_utf8_and_rejects_invalid_ranges :: proc(t: ^testing.T) {
	edit_search(nil)
	defer close_search()
	append_search_text("café movie")
	erase_search_text(-6, 6)
	testing.expect_value(t, strings.to_string(search_text), "café")
	// A partial UTF-8 character must not corrupt the query.
	erase_search_text(-1, 1)
	testing.expect_value(t, strings.to_string(search_text), "café")
	erase_search_text(-2, 2)
	testing.expect_value(t, strings.to_string(search_text), "caf")
	erase_search_text(-99, 2)
	erase_search_text(0, 10)
	testing.expect_value(t, strings.to_string(search_text), "caf")
	append_search_text("é movie")
	erase_search_text(-8, 2)
	append_search_text("!")
	testing.expect_value(t, strings.to_string(search_text), "caf movie!")
	erase_search_text(0, max(u32))
	testing.expect_value(t, strings.builder_len(search_text), 0)
	append_search_text("café movie")
	search_key(sdl.K_HOME, nil)
	for _ in 0 ..< 3 {search_key(sdl.K_RIGHT, nil)}
	erase_search_text(0, 2)
	append_search_text("!")
	testing.expect_value(t, strings.to_string(search_text), "caf! movie")
}

@(test)
search_keys_move_select_and_edit_complete_graphemes :: proc(t: ^testing.T) {
	edit_search(nil)
	defer close_search()
	append_search_text("café")
	search_key(sdl.K_LEFT, nil)
	append_search_text("!")
	testing.expect_value(t, strings.to_string(search_text), "caf!é")
	search_key(sdl.K_DELETE, nil)
	testing.expect_value(t, strings.to_string(search_text), "caf!")
	search_key(sdl.K_HOME, nil)
	search_key(sdl.K_RIGHT, nil)
	search_key(sdl.K_RIGHT, nil, sdl.KMOD_LSHIFT)
	append_search_text("o")
	testing.expect_value(t, strings.to_string(search_text), "cof!")
	search_key(sdl.K_END, nil)
	search_key(sdl.K_BACKSPACE, nil)
	append_search_text("e\u0301")
	search_key(sdl.K_BACKSPACE, nil)
	testing.expect_value(t, strings.to_string(search_text), "cof")
}
