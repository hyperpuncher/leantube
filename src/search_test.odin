package main

import "./model"
import "core:strings"
import "core:sync/chan"
import "core:testing"
import sdl "vendor:sdl3"

@(test)
search_input_replaces_the_old_query_and_deletes_complete_utf8_characters :: proc(t: ^testing.T) {
	catalog.query = strings.clone("old query")
	defer {model.catalog_destroy(&catalog); delete(search_text); search_text = nil
		search_editing = false}
	edit_search(nil)
	oversized := make([]u8, 513)
	defer delete(oversized)
	append_search_text(string(oversized))
	testing.expect_value(t, string(search_text[:]), "old query")
	testing.expect(t, search_replace)
	append_search_text("café")
	testing.expect_value(t, string(search_text[:]), "café")
	search_key(sdl.K_BACKSPACE, nil)
	testing.expect_value(t, string(search_text[:]), "caf")
	search_key(sdl.K_AC_BACK, nil)
	testing.expect(t, !search_editing)
	testing.expect_value(t, catalog.query, "old query")
	append_search_text("ignored")
	testing.expect_value(t, string(search_text[:]), "caf")
}

@(test)
new_input_replaces_pending_work_and_stale_results_do_not_replace_the_page :: proc(t: ^testing.T) {
	defer {stop_network(); model.catalog_destroy(&catalog); page = 0}
	network_requests, _ = chan.create(chan.Chan(Network_Request), 1, context.allocator)
	network_results, _ = chan.create(chan.Chan(Network_Result), 2, context.allocator)
	testing.expect(t, submit_network({kind = .Search, text = strings.clone("old")}))
	testing.expect(t, submit_network({kind = .Search, text = strings.clone("new")}))
	request, ok := chan.try_recv(network_requests)
	testing.expect(t, ok)
	testing.expect_value(t, request.text, "new")
	delete(request.text)
	page = 2
	catalog.query = strings.clone("current")
	stale := Network_Result {
		kind = .Catalog,
		page = 1,
		catalog = {query = strings.clone("stale")},
	}
	chan.send(network_results, stale)
	poll_network(nil)
	testing.expect_value(t, catalog.query, "current")
}
