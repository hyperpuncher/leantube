#+test
package main

import clay "../vendor/clay"
import "./model"
import "core:strings"
import "core:sync/chan"
import "core:testing"
import sdl "vendor:sdl3"

@(test)
channel_sort_keeps_header_and_back_restores_the_origin_feed :: proc(t: ^testing.T) {
	previous_context := clay.GetCurrentContext()
	memory := make([]u8, int(clay.MinMemorySize()))
	clay.Initialize(
		clay.CreateArenaWithCapacityAndMemory(uint(len(memory)), raw_data(memory)),
		{1920, 1080},
		{handler = clay_error},
	)
	defer {clay.SetCurrentContext(previous_context); delete(memory)}
	network_requests, _ = chan.create(chan.Chan(Network_Request), 2, context.allocator)
	network_results, _ = chan.create(chan.Chan(Network_Result), 2, context.allocator)
	defer {
		stop_network(); clear_catalog(); clear_browse_history()
		delete(browse_id); delete(browse_params); delete(browse_filter)
		browse_id, browse_params, browse_filter = "", "", ""
		channel_focus, search_loading = false, false
		restore_selected, page, selected = -1, 0, 0
	}
	browsing = true
	account_menu, login_screen, search_editing, rail_focus = false, false, false, false
	browse_id = strings.clone("FEsubscriptions")
	selected = 5
	start_browse("UC-example", "videos-param")
	request, ok := chan.try_recv(network_requests)
	if !testing.expect(t, ok) {return}
	free_network_request(&request)
	testing.expect_value(t, len(browse_history), 1)
	response := Network_Result {
		kind = .Catalog,
		page = page,
	}
	response.catalog.channel = {
		id    = strings.clone("UC-example"),
		title = strings.clone("A channel"),
	}
	append(
		&response.catalog.channel.tabs,
		model.Channel_Option {
			label = strings.clone("Videos"),
			params = strings.clone("videos-param"),
			selected = true,
		},
	)
	append(
		&response.catalog.channel.sorts,
		model.Channel_Option {
			label = strings.clone("Newest"),
			token = strings.clone("newest-token"),
			selected = true,
		},
		model.Channel_Option {
			label = strings.clone("Popular"),
			token = strings.clone("popular-token"),
		},
	)
	append(&response.catalog.videos, model.Video{title = strings.clone("Newest video")})
	chan.send(network_results, response)
	poll_network(nil)

	activate_channel_option(2)
	request, ok = chan.try_recv(network_requests)
	if !testing.expect(t, ok) {return}
	defer free_network_request(&request)
	testing.expect_value(t, request.params, "videos-param")
	testing.expect_value(t, request.filter, "popular-token")
	testing.expect_value(t, request.continuation, "")
	testing.expect_value(t, len(browse_history), 1)
	testing.expect_value(t, catalog.channel.title, "A channel")
	response = {
		kind = .Catalog,
		page = page,
	}
	response.catalog.channel.id = strings.clone("UC-example")
	append(
		&response.catalog.channel.sorts,
		model.Channel_Option {
			label = strings.clone("Newest"),
			token = strings.clone("newest-updated"),
		},
		model.Channel_Option {
			label = strings.clone("Popular"),
			token = strings.clone("popular-updated"),
			selected = true,
		},
	)
	append(&response.catalog.videos, model.Video{title = strings.clone("Popular video")})
	chan.send(network_results, response)
	poll_network(nil)
	testing.expect_value(t, catalog.channel.title, "A channel")
	if !testing.expect_value(t, len(catalog.channel.sorts), 2) {return}
	testing.expect(t, catalog.channel.sorts[1].selected)
	testing.expect_value(t, catalog.channel.sorts[1].token, "popular-updated")
	if !testing.expect_value(t, len(catalog.videos), 1) {return}
	testing.expect_value(t, catalog.videos[0].title, "Popular video")

	key(sdl.K_AC_BACK)
	back, ready := chan.try_recv(network_requests)
	if !testing.expect(t, ready) {return}
	defer free_network_request(&back)
	testing.expect_value(t, back.text, "FEsubscriptions")
	testing.expect_value(t, back.filter, "")
	testing.expect_value(t, len(browse_history), 0)
	testing.expect_value(t, catalog.channel.title, "")
	response = {
		kind = .Catalog,
		page = page,
	}
	resize(&response.catalog.videos, 6)
	chan.send(network_results, response)
	poll_network(nil)
	testing.expect_value(t, selected, 5)
}
