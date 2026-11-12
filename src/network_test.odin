#+test
package main

import clay "../vendor/clay"
import "./model"
import sb "./sponsorblock"
import "core:os"
import "core:strings"
import "core:sync/chan"
import "core:testing"
import sdl "vendor:sdl3"

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
	old_segments := make([dynamic]sb.Segment)
	append(&old_segments, sb.Segment{start_ms = 0, end_ms = 1000})
	chan.send(
		network_results,
		Network_Result {
			kind = .Stream,
			page = first.page,
			playback = first.playback,
			error = .No_Direct_Stream,
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
	network_requests, _ = chan.create(chan.Chan(Network_Request), 1, context.allocator)
	network_results, _ = chan.create(chan.Chan(Network_Result), 2, context.allocator)
	defer {stop_network(); clear_catalog(); page = 0; selected = 0; delete(browse_id)
		browse_id = ""}
	page = 4
	append(
		&catalog.videos,
		model.Video{id = strings.clone("DN953UW8iJ8"), title = strings.clone("first")},
	)
	catalog.continuation = strings.clone("old-continuation")
	resize(&textures, 1)
	for result_page in ([]u32{3, 4}) {
		result := Network_Result {
			kind   = .Catalog,
			page   = result_page,
			append = true,
		}
		// Continuations can repeat cards from an earlier page.
		for fixture, index in ([2]struct {
				id, title: string,
			}{{"DN953UW8iJ8", "overlap"}, {"C5WDBA2i9nE", "next"}}) {
			append(
				&result.catalog.videos,
				model.Video {
					id = strings.clone(fixture.id),
					title = strings.clone(fixture.title),
					cover_index = 1 + index,
				},
			)
		}
		result.catalog.continuation = strings.clone("new-continuation")
		chan.send(network_results, result)
		poll_network(nil)
		testing.expect_value(t, len(catalog.videos), result_page == page ? 2 : 1)
	}
	testing.expect_value(t, len(textures), 2)
	testing.expect_value(t, catalog.videos[0].title, "first")
	testing.expect_value(t, catalog.videos[1].title, "next")
	testing.expect_value(t, catalog.videos[1].cover_index, 1)
	testing.expect_value(t, catalog.continuation, "new-continuation")
	images, images_requested := chan.try_recv(network_requests)
	defer free_network_request(&images)
	if testing.expect(t, images_requested && images.kind == .Images && len(images.images) == 1) {
		testing.expect_value(t, images.images[0].index, 1)
		testing.expect_value(t, images.images[0].source, "C5WDBA2i9nE")
	}
	repeated := Network_Result {
		kind = .Catalog,
		page = page,
		append = true,
		catalog = {continuation = strings.clone("after-overlap")},
	}
	append(
		&repeated.catalog.videos,
		model.Video{id = strings.clone("C5WDBA2i9nE"), title = strings.clone("another overlap")},
	)
	chan.send(network_results, repeated)
	poll_network(nil)
	testing.expect_value(t, len(catalog.videos), 2)
	testing.expect_value(t, len(textures), 2)
	testing.expect_value(t, catalog.continuation, "after-overlap")
	// Removing from Watch later must not remove a subscription card.
	browse_id = strings.clone("FEsubscriptions")
	for current_playlist in ([2]bool{false, true}) {
		if current_playlist {delete(browse_id); browse_id = strings.clone("VLWL")}
		card_action_cover, card_action_done_until = 0, 1
		card_menu_selected = 0
		append(
			&card_menu_actions,
			model.card_action_clone({kind = .Edit_Playlist, target = "WL", remove = true}),
		)
		dismiss_card_menu()
		testing.expect_value(t, len(catalog.videos), current_playlist ? 1 : 2)
	}
	testing.expect_value(t, catalog.videos[0].cover_index, 1)
	testing.expect_value(t, len(textures), 2)
	testing.expect_value(t, page, u32(4))
	testing.expect_value(t, catalog.continuation, "after-overlap")
	unexpected, requested := chan.try_recv(network_requests)
	defer free_network_request(&unexpected)
	testing.expect(t, !requested, "local removal must not request another page")
	result := Network_Result {
		kind   = .Catalog,
		page   = page,
		append = true,
	}
	append(
		&result.catalog.videos,
		model.Video{title = strings.clone("after removal"), cover_index = 2},
	)
	chan.send(network_results, result)
	poll_network(nil)
	testing.expect_value(t, catalog.videos[0].title, "next")
	testing.expect_value(t, catalog.videos[1].cover_index, 2)
	testing.expect_value(t, len(textures), 3)
	remove_catalog_card(1)
	remove_catalog_card(2)
	testing.expect_value(t, len(catalog.videos), 0)
	testing.expect_value(t, selected, 0)
}

@(test)
search_pagination_uses_the_search_endpoint_and_sends_the_continuation :: proc(t: ^testing.T) {
	network_requests, _ = chan.create(chan.Chan(Network_Request), 1, context.allocator)
	defer {stop_network(); clear_catalog(); search_loading = false}
	catalog.query = strings.clone("query")
	catalog.continuation = strings.clone("search-next")
	load_more()
	request, ok := chan.try_recv(network_requests)
	defer free_network_request(&request)
	testing.expect(t, ok && request.kind == .Search)
	testing.expect_value(t, request.text, "query")
	testing.expect_value(t, request.continuation, "search-next")
}

@(test)
full_queues_preserve_account_and_browse_order :: proc(t: ^testing.T) {
	network_requests, _ = chan.create(chan.Chan(Network_Request), 2, context.allocator)
	defer stop_network()
	request := Network_Request {
		kind = .Use_Account,
		auth_token = {access_token = strings.clone("test-only-token")},
	}
	testing.expect(t, submit_network(request))
	testing.expect(t, submit_network({kind = .Browse, text = strings.clone("existing page")}))
	testing.expect(t, !submit_network({kind = .Search, text = strings.clone("query")}))
	retained, ok := chan.try_recv(network_requests)
	defer free_network_request(&retained)
	testing.expect(t, ok)
	testing.expect_value(t, retained.kind, .Use_Account)
	testing.expect_value(t, retained.auth_token.access_token, "test-only-token")
	next, next_ok := chan.try_recv(network_requests)
	defer free_network_request(&next)
	testing.expect(t, next_ok)
	testing.expect_value(t, next.kind, .Browse)
	testing.expect_value(t, next.text, "existing page")
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
	testing.expect_value(t, notice, "")
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
decoded_covers_upload_reuse_and_reject_stale_results :: proc(t: ^testing.T) {
	output := sdl.CreateSurface(160, 120, .RGBA32)
	if !testing.expect(t, output != nil) {return}
	defer sdl.DestroySurface(output)
	renderer := sdl.CreateSoftwareRenderer(output)
	if !testing.expect(t, renderer != nil) {return}
	defer sdl.DestroyRenderer(renderer)
	network_requests, _ = chan.create(chan.Chan(Network_Request), 1, context.allocator)
	network_results, _ = chan.create(chan.Chan(Network_Result), 1, context.allocator)
	defer {stop_network(); clear_catalog(); page = 0}
	page = 4
	append(&catalog.videos, model.Video{})
	resize(&textures, 1)
	for fixture in ([]struct {
			file:    cstring,
			page:    u32,
			index:   int,
			replace: bool,
		} {
			{"tests/ui/cover.webp", 4, 0, true},
			{"tests/ui/cover.jpg", 3, 0, false}, // Stale page.
			{"tests/ui/cover.jpg", 4, 1, false}, // Missing card.
			{"tests/ui/cover.jpg", 4, 0, true},
		}) {
		bytes, error := os.read_entire_file(string(fixture.file), context.allocator)
		if !testing.expect(t, error == nil) {return}
		image := decode_image(bytes)
		delete(bytes)
		if !testing.expect(t, image != nil) {return}
		expected_width, expected_height := f32(image.w), f32(image.h)
		previous := textures[0]
		chan.send(
			network_results,
			Network_Result {
				kind = .Cover,
				page = fixture.page,
				index = fixture.index,
				surface = image,
			},
		)
		poll_network(renderer)
		if !fixture.replace {
			testing.expect_value(t, textures[0], previous)
			continue
		}
		if !testing.expect(t, textures[0] != nil) {return}
		width, height: f32
		testing.expect(t, sdl.GetTextureSize(textures[0], &width, &height))
		testing.expect_value(t, width, expected_width)
		testing.expect_value(t, height, expected_height)
	}
	original := textures[0]
	source :: "https://images.example/cover"
	retain_image_texture(image_key(source, 0), original)
	for changed in ([2]bool{false, true}) {
		clear_catalog()
		result := Network_Result {
			kind = .Catalog,
			page = page,
		}
		append(
			&result.catalog.videos,
			model.Video{thumbnail_url = strings.clone(changed ? source + "-new" : source)},
		)
		chan.send(network_results, result)
		poll_network(renderer)
		if changed {
			testing.expect(t, textures[0] == nil, "a changed image URL must be loaded again")
			request, ready := chan.try_recv(network_requests)
			defer free_network_request(&request)
			testing.expect(t, ready && request.kind == .Images && len(request.images) == 1)
		} else {
			testing.expect_value(t, textures[0], original)
			testing.expect(
				t,
				sdl.RenderTexture(renderer, textures[0], nil, nil) && sdl.RenderPresent(renderer),
			)
			unexpected, requested := chan.try_recv(network_requests)
			defer free_network_request(&unexpected)
			testing.expect(t, !requested, "a retained image must not be decoded or uploaded again")
		}
	}
}

@(test)
playing_controls_hide_only_while_playing :: proc(t: ^testing.T) {
	previous_context := clay.GetCurrentContext()
	memory := make([]u8, int(clay.MinMemorySize()))
	clay.Initialize(
		clay.CreateArenaWithCapacityAndMemory(uint(len(memory)), raw_data(memory)),
		{1920, 1080},
		{handler = clay_error},
	)
	defer {clay.SetCurrentContext(previous_context); delete(memory)}
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
