#+test
package main

import "./model"
import sb "./sponsorblock"
import "core:strings"
import "core:sync/chan"
import "core:testing"

@(test)
canceling_and_reopening_the_same_video_rejects_old_replies :: proc(t: ^testing.T) {
	network_requests, _ = chan.create(chan.Chan(Network_Request), 1, context.allocator)
	network_results, _ = chan.create(chan.Chan(Network_Result), 2, context.allocator)
	defer {
		stop_network(); stop_playback(); clear_catalog()
		page, playback = 0, 0
		notice = ""
	}
	append(&catalog.videos, model.Video{id = strings.clone("C5WDBA2i9nE")})
	selected = 0
	resolve_selected()
	first, first_ok := chan.try_recv(network_requests)
	defer delete(first.text)
	stop_playback()
	resolve_selected()
	second, second_ok := chan.try_recv(network_requests)
	defer delete(second.text)
	testing.expect(t, first_ok && second_ok)
	testing.expect(t, first.playback != second.playback)
	chan.send(
		network_results,
		Network_Result {
			kind = .Stream,
			page = first.page,
			playback = first.playback,
			error = .No_Direct_Stream,
		},
	)
	old_segments := make([dynamic]sb.Segment)
	append(&old_segments, sb.Segment{start_ms = 0, end_ms = 1000})
	chan.send(
		network_results,
		Network_Result {
			kind = .Segments,
			page = first.page,
			playback = first.playback,
			segments = old_segments,
		},
	)
	poll_network(nil)
	testing.expect(t, resolving && !browsing)
	testing.expect_value(t, len(sponsor_segments), 0)
	chan.send(
		network_results,
		Network_Result {
			kind = .Stream,
			page = second.page,
			playback = second.playback,
			error = .No_Direct_Stream,
		},
	)
	poll_network(nil)
	testing.expect(t, !resolving && browsing)
	testing.expect(t, notice != "")
}

@(test)
continuation_appends_cards_and_rejects_stale_pages :: proc(t: ^testing.T) {
	network_results, _ = chan.create(chan.Chan(Network_Result), 2, context.allocator)
	defer {stop_network(); clear_catalog(); page = 0; selected = 0}
	page = 4
	append(&catalog.videos, model.Video{title = strings.clone("first")})
	catalog.continuation = strings.clone("old-continuation")
	resize(&textures, 1)
	for result_page in ([]u32{3, 4}) {
		result := Network_Result {
			kind   = .Catalog,
			page   = result_page,
			append = true,
		}
		append(&result.catalog.videos, model.Video{title = strings.clone("next")})
		result.catalog.continuation = strings.clone("new-continuation")
		chan.send(network_results, result)
		poll_network(nil)
		testing.expect_value(t, len(catalog.videos), result_page == page ? 2 : 1)
	}
	testing.expect_value(t, len(textures), 2)
	testing.expect_value(t, catalog.videos[0].title, "first")
	testing.expect_value(t, catalog.videos[1].title, "next")
	testing.expect_value(t, catalog.continuation, "new-continuation")
}

@(test)
queued_account_changes_are_not_discarded_by_page_requests :: proc(t: ^testing.T) {
	network_requests, _ = chan.create(chan.Chan(Network_Request), 1, context.allocator)
	defer stop_network()
	request := Network_Request {
		kind = .Use_Account,
		auth_token = {access_token = strings.clone("test-only-token")},
	}
	testing.expect(t, submit_network(request))
	testing.expect(t, !submit_network({kind = .Search, text = strings.clone("query")}))
	retained, ok := chan.try_recv(network_requests)
	defer free_network_request(&retained)
	testing.expect(t, ok)
	testing.expect_value(t, retained.kind, .Use_Account)
	testing.expect_value(t, retained.auth_token.access_token, "test-only-token")
}

@(test)
search_errors_empty_results_and_recovery_finish_loading :: proc(t: ^testing.T) {
	network_results, _ = chan.create(chan.Chan(Network_Result), 2, context.allocator)
	defer {
		stop_network(); clear_catalog()
		page = 0; search_loading = false; notice = ""
	}
	page = 3
	search_loading = true
	catalog.query = strings.clone("current query")
	chan.send(network_results, Network_Result{kind = .Catalog, page = page, error = .Transport})
	poll_network(nil)
	testing.expect(t, !search_loading && notice != "")
	testing.expect_value(t, catalog.query, "current query")
	search_loading = true
	chan.send(
		network_results,
		Network_Result {
			kind = .Catalog,
			page = page,
			catalog = {query = strings.clone("empty query")},
		},
	)
	poll_network(nil)
	testing.expect(t, !search_loading)
	testing.expect_value(t, len(catalog.videos), 0)
	testing.expect_value(t, notice, "no items found")
	result := Network_Result {
		kind = .Catalog,
		page = page,
		catalog = {query = strings.clone("recovered query")},
	}
	append(&result.catalog.videos, model.Video{title = strings.clone("recovered video")})
	search_loading = true
	chan.send(network_results, result)
	poll_network(nil)
	testing.expect(t, !search_loading && notice == "")
	testing.expect_value(t, catalog.query, "recovered query")
	testing.expect_value(t, len(catalog.videos), 1)
}

@(test)
playing_controls_hide_only_while_playing :: proc(t: ^testing.T) {
	saved_browsing, saved_paused, saved_loaded := browsing, paused, loaded
	saved_until := controls_until
	defer {
		browsing, paused, loaded = saved_browsing, saved_paused, saved_loaded
		controls_until = saved_until
	}
	browsing, loaded, paused = false, true, false
	show_player_controls()
	testing.expect(t, player_controls_visible())
	controls_until = 0
	testing.expect(t, !player_controls_visible())
	paused = true
	testing.expect(t, player_controls_visible())
	browsing, paused, controls_until = true, false, 0
	expire_player_controls()
	testing.expect_value(t, controls_until, u64(0))
}
