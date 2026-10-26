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
	testing.expect_value(t, notice, "no videos found")
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
