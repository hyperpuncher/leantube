package main

import "core:testing"

@(test)
ime_deletion_preserves_utf8_and_rejects_invalid_ranges :: proc(t: ^testing.T) {
	search_editing = true
	search_replace = false
	defer {delete(search_text); search_text = nil; search_editing = false}
	append_search_text("café movie")
	erase_search_text(-6, 6)
	testing.expect_value(t, string(search_text[:]), "café")
	// A partial UTF-8 character must not corrupt the query.
	erase_search_text(-1, 1)
	testing.expect_value(t, string(search_text[:]), "café")
	erase_search_text(-2, 2)
	testing.expect_value(t, string(search_text[:]), "caf")
	erase_search_text(-99, 2)
	erase_search_text(0, 10)
	testing.expect_value(t, string(search_text[:]), "caf")
	erase_search_text(0, max(u32))
	testing.expect_value(t, len(search_text), 0)
}
