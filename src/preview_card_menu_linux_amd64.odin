package main

import clay "../vendor/clay"
import "./model"
import "core:strings"
import "core:sync/chan"
import sdl "vendor:sdl3"

check_watch_later_ui :: proc(renderer: ^sdl.Renderer, surface: ^sdl.Surface) {
	saved_signed_in, saved_notice := signed_in, notice
	signed_in = true
	saved_membership := catalog.videos[selected].watch_later
	catalog.videos[selected].watch_later = .Unknown
	defer {catalog.videos[selected].watch_later = saved_membership}
	network_requests, _ = chan.create(chan.Chan(Network_Request), 1, context.allocator)
	network_results, _ = chan.create(chan.Chan(Network_Result), 1, context.allocator)
	defer {
		stop_network()
		close_card_menu()
		signed_in, notice = saved_signed_in, saved_notice
		clay.SetPointerState({-1, -1}, false)
		assert(render(renderer))
	}
	assert(render(renderer))
	assert(!clay.GetElementData(clay.ID("watch-later", 0)).found)
	cover := clay.GetElementData(clay.ID("cover", 0)).boundingBox
	controls_pointer(renderer, cover.x + cover.width / 2, cover.y + scaled(16), false, false)
	snapshot(renderer, surface, "watch-later-hover")
	button := clay.GetElementData(clay.ID("watch-later", 0))
	assert(button.found)
	x := button.boundingBox.x + button.boundingBox.width / 2
	y := button.boundingBox.y + button.boundingBox.height / 2
	controls_pointer(renderer, x, y, false, false)
	assert(render(renderer))
	assert(clay.GetElementData(clay.ID("watch-later", 0)).found)
	_, hovered_request := chan.try_recv(network_requests)
	assert(!hovered_request, "hover must not fetch membership")
	catalog.videos[selected].watch_later = .Absent
	// Clicking a known overlay must submit one save, never start playback.
	controls_pointer(renderer, x, y, true, true)
	controls_pointer(renderer, x, y, true, true)
	finish_card_press(true, sdl.GetTicks())
	request, ok := chan.try_recv(network_requests)
	assert(ok && request.kind == .Card_Action && request.action.target == "WL")
	defer free_network_request(&request)
	_, duplicate := chan.try_recv(network_requests)
	assert(!duplicate && card_menu_waiting && !card_menu && browsing && !loaded)
	// A failed save stays retryable without reloading the feed.
	chan.send(
		network_results,
		Network_Result {
			kind = .Card_Action,
			page = page,
			index = request.index,
			error = .Transport,
		},
	)
	poll_network(renderer)
	assert(!card_menu_waiting && notice != "" && !search_loading)
	controls_pointer(renderer, x, y, true, true)
	retry, retry_ok := chan.try_recv(network_requests)
	assert(retry_ok)
	defer free_network_request(&retry)
	chan.send(
		network_results,
		Network_Result{kind = .Card_Action, page = page, index = retry.index},
	)
	poll_network(renderer)
	assert(
		notice == "" &&
		card_action_done_until > sdl.GetTicks() &&
		!card_menu_waiting &&
		!card_menu &&
		browsing &&
		!loaded &&
		!search_loading,
	)
	snapshot(renderer, surface, "watch-later-saved")
	assert(
		clay.GetElementData(clay.ID("cover", 0)).boundingBox == cover,
		"saving must not move the grid",
	)
	poll_card_press(card_action_done_until)
	assert(card_action_done_until == 0 && catalog.videos[selected].watch_later == .Present)
	snapshot(renderer, surface, "watch-later-reset")
}

check_card_menu_ui :: proc(renderer: ^sdl.Renderer, surface: ^sdl.Surface) {
	// In-memory channels exercise the TV popup without sending mutations to YouTube.
	saved_id := catalog.videos[selected].id
	catalog.videos[selected].id = strings.clone("DN953UW8iJ8")
	defer {delete(catalog.videos[selected].id); catalog.videos[selected].id = saved_id}
	saved_actions := catalog.videos[selected].actions
	saved_membership := catalog.videos[selected].watch_later
	catalog.videos[selected].watch_later = .Absent
	catalog.videos[selected].actions = nil
	defer {
		close_card_menu()
		model.card_actions_destroy(&catalog.videos[selected].actions)
		catalog.videos[selected].actions = saved_actions
		catalog.videos[selected].watch_later = saved_membership
	}
	for action in ([]model.Card_Action{{kind = .Edit_Playlist, label = "Save to Watch later", target = "WL"}, {kind = .Playlists, label = "Save to playlist"}, {kind = .Browse, label = "Go to channel"}, {kind = .Feedback, label = "Hide"}}) {
		append(&catalog.videos[selected].actions, model.card_action_clone(action))
	}
	open_card_menu()
	snapshot(renderer, surface, "card-menu")
	menu := clay.GetElementData(clay.ID("card-menu"))
	assert(menu.found, "the popup must exist")
	box := menu.boundingBox
	assert(
		box.width > 0 &&
		box.height > 0 &&
		box.x >= 0 &&
		box.y >= 0 &&
		box.x + box.width <= view_width &&
		box.y + box.height <= view_height,
	)
	last := len(card_menu_actions) - 1
	for _ in 0 ..< last {key(sdl.K_DOWN)}
	snapshot(renderer, surface, "card-menu-last")
	item := clay.GetElementData(clay.ID("card-action", u32(last)))
	scroll := clay.GetElementData(clay.ID("card-menu-scroll"))
	assert(item.found && scroll.found, "the selected row and scroll viewport must exist")
	row, viewport := item.boundingBox, scroll.boundingBox
	assert(row.height > 0 && row.width > 0 && viewport.height > 0)
	assert(row.y >= viewport.y && row.y + row.height <= viewport.y + viewport.height)
	assert(card_menu_selected == last && card_menu)
	key(sdl.K_AC_BACK)
	assert(!card_menu && browsing, "back must dismiss the popup without closing the library")

	// A menu action replaces only its icon while pending and after success.
	network_requests, _ = chan.create(chan.Chan(Network_Request), 1, context.allocator)
	network_results, _ = chan.create(chan.Chan(Network_Result), 1, context.allocator)
	saved_signed_in := signed_in
	signed_in = true
	defer {stop_network(); signed_in = saved_signed_in}
	open_card_menu()
	assert(render(renderer))
	box = clay.GetElementData(clay.ID("card-menu")).boundingBox
	key(sdl.K_RETURN)
	request, ready := chan.try_recv(network_requests)
	assert(ready && request.kind == .Card_Action && card_menu_waiting)
	defer free_network_request(&request)
	snapshot(renderer, surface, "card-menu-pending")
	assert(clay.GetElementData(clay.ID("card-menu")).boundingBox == box)
	chan.send(
		network_results,
		Network_Result{kind = .Card_Action, page = page, index = request.index},
	)
	poll_network(renderer)
	assert(card_menu && !card_menu_waiting && card_action_done_until > sdl.GetTicks())
	snapshot(renderer, surface, "card-menu-saved")
	assert(clay.GetElementData(clay.ID("card-menu")).boundingBox == box)
	key(sdl.K_RETURN)
	_, duplicate := chan.try_recv(network_requests)
	assert(!duplicate, "the checkmark must not submit the action twice")
	key(sdl.K_AC_BACK)
	_, reloaded := chan.try_recv(network_requests)
	assert(!reloaded, "saving must not reload the feed")

	// Unknown membership is read once on opening, then retained with the card.
	catalog.videos[selected].watch_later = .Unknown
	open_card_menu()
	membership, requested := chan.try_recv(network_requests)
	assert(requested && membership.kind == .Card_Membership)
	defer free_network_request(&membership)
	result := Network_Result {
		kind  = .Card_Membership,
		page  = page,
		index = membership.index,
	}
	append(
		&result.actions,
		model.card_action_clone({kind = .Edit_Playlist, target = "WL", remove = true}),
	)
	chan.send(network_results, result)
	poll_network(renderer)
	assert(catalog.videos[selected].watch_later == .Present)
	assert(card_menu_actions[0].remove && card_menu_actions[0].label == "Remove from Watch later")
	snapshot(renderer, surface, "card-menu-remove-watch-later")
	close_card_menu()
	open_card_menu()
	_, repeated := chan.try_recv(network_requests)
	assert(!repeated, "known membership must not be fetched again")
	close_card_menu()

	// Moving onto the rail must cancel a hold before its input handler returns.
	render(renderer)
	begin_card_press(true, 1000)
	assert(card_press.active)
	navigation := clay.GetElementData(clay.ID("navigation-item", u32(Navigation.Home)))
	assert(navigation.found)
	x, y: f32
	assert(
		sdl.RenderCoordinatesToWindow(
			renderer,
			navigation.boundingBox.x + navigation.boundingBox.width / 2,
			navigation.boundingBox.y + navigation.boundingBox.height / 2,
			&x,
			&y,
		),
	)
	controls_pointer(renderer, x, y, true, false)
	poll_card_press(1000 + CARD_HOLD_MS)
	assert(!card_press.active && !card_menu, "leaving the card must cancel its hold")
}
