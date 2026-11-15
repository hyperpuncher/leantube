#+build linux:default amd64, linux:default arm64
package main

import clay "../vendor/clay"
import "./model"
import "core:c"
import "core:math"
import "core:strings"
import "core:sync/chan"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

check_search_flow :: proc(renderer: ^sdl.Renderer, surface: ^sdl.Surface) {
	network_requests, _ = chan.create(chan.Chan(Network_Request), 1, context.allocator)
	network_results, _ = chan.create(chan.Chan(Network_Result), 2, context.allocator)
	defer stop_network()
	selected = 0
	viewport := clay.GetElementData(clay.ID("library-scroll")).boundingBox
	key(sdl.K_TAB)
	assert(search_editing)
	event: sdl.Event
	event.type = .TEXT_INPUT
	event.text.text = "café"
	handle_event(renderer, event)
	assert(strings.to_string(search_text) == "café")
	event = {}
	event.type = .KEY_DOWN
	event.key.raw = 412
	handle_event(renderer, event)
	assert(!search_editing && running && browsing)
	assert(catalog.query != "café", "back must cancel text entry without changing the page")
	key(sdl.K_TAB)
	event = {}
	event.type = .TEXT_INPUT
	event.text.text = "Linus Tech Tips"
	handle_event(renderer, event)
	snapshot(renderer, surface, "search-edit")
	assert(
		clay.GetElementData(clay.ID("library-scroll")).boundingBox == viewport,
		"opening search must not move the feed",
	)
	long_query := strings.repeat("café", 90)
	defer delete(long_query)
	for sample in ([2]string{"", long_query}) {
		erase_search_text(0, max(u32))
		append_search_text(sample)
		snapshot(renderer, surface, sample == "" ? "search-edit-empty" : "search-edit-long")
		if sample == long_query {
			input := clay.GetElementData(clay.ID("search-text")).boundingBox
			x, y := i32(input.x + input.width - 1), i32(input.y + input.height / 2)
			pixel: u8
			assert(sdl.ReadSurfacePixel(surface, x, y, &pixel, nil, nil, nil))
			assert(pixel == u8(COLOR_TEXT[0]), "long input must keep the caret visible")
		}
	}
	// Regressions from the two reported caret-overlap examples.
	for sample in ([2]string{"lih", "ltn"}) {
		erase_search_text(0, max(u32))
		append_search_text(sample)
		search_key(sdl.K_LEFT, nil)
		snapshot(
			renderer,
			surface,
			sample == "lih" ? "search-edit-caret-lih" : "search-edit-caret-ltn",
		)
		text := ttf.CreateText(nil, fonts[.Heading], raw_data(sample), c.size_t(len(sample)))
		assert(text != nil)
		defer ttf.DestroyText(text)
		left, right: ttf.SubString
		assert(ttf.GetTextSubString(text, 1, &left))
		assert(ttf.GetTextSubString(text, 2, &right))
		caret, ok := search_text_x(text, 2)
		assert(ok)
		caret_left := math.round(caret - SEARCH_CARET_WIDTH / 2)
		assert(
			caret_left >= f32(left.rect.x + left.rect.w) &&
			caret_left + SEARCH_CARET_WIDTH <= f32(right.rect.x),
			"caret must not overlap either letter",
		)
		input := clay.GetElementData(clay.ID("search-text")).boundingBox
		controls_pointer(renderer, input.x + caret, input.y + input.height / 2, true, true)
		assert(
			search_editor.selection == ([2]int{2, 2}),
			"click must preserve the insertion boundary",
		)
	}
	erase_search_text(0, max(u32))
	append_search_text("Linus Tech Tips")
	// Exercise SDL modifier routing, not only the editor's key handler.
	event = {}
	event.type = .KEY_DOWN
	event.key.key = sdl.K_HOME
	handle_event(renderer, event)
	event.key.key = sdl.K_RIGHT
	event.key.mod = sdl.KMOD_LSHIFT
	handle_event(renderer, event)
	snapshot(renderer, surface, "search-edit-selection")
	assert(search_editor.selection == ([2]int{1, 0}))
	input := clay.GetElementData(clay.ID("search-text")).boundingBox
	controls_pointer(renderer, input.x + scaled(1), input.y + input.height / 2, true, true)
	assert(search_editor.selection == ([2]int{0, 0}))
	snapshot(renderer, surface, "search-edit-caret-start")
	x, y := i32(math.round(input.x)), i32(input.y + input.height / 2)
	pixel: u8
	assert(sdl.ReadSurfacePixel(surface, x, y, &pixel, nil, nil, nil))
	assert(pixel == u8(COLOR_TEXT[0]), "caret must move to the clicked position")
	// The backdrop must block scrolling and navigation behind the search field.
	home := clay.GetElementData(clay.ID("navigation-item", u32(Navigation.Home))).boundingBox
	home_x, home_y := home.x + home.width / 2, home.y + home.height / 2
	scroll := clay.GetScrollContainerData(clay.ID("library-scroll"))
	before := scroll.scrollPosition^[1]
	event = {}
	event.type = .MOUSE_WHEEL
	event.wheel.mouse_x = viewport.x + viewport.width - scaled(32)
	event.wheel.mouse_y = viewport.y + viewport.height / 2
	event.wheel.y = -3
	wheel := handle_event(renderer, event)
	assert(render(renderer, wheel))
	assert(scroll.scrollPosition^[1] == before, "search must block background scrolling")
	saved_page := page
	controls_pointer(renderer, home_x, home_y, true, true)
	assert(!search_editing && page == saved_page, "outside click must dismiss without navigating")
	edit_search(nil)
	append_search_text("Linus Tech Tips")
	search_key(sdl.K_END, nil)
	for state in 0 ..< 3 {
		key(sdl.K_RETURN)
		assert(search_loading && !search_editing && len(catalog.videos) == 0)
		assert(loading_active(), "initial loading must still animate its spinner")
		if state == 0 {snapshot(renderer, surface, "search-loading")}
		request, ready := chan.try_recv(network_requests)
		assert(ready && request.text == "Linus Tech Tips")
		defer delete(request.text)
		result := Network_Result {
			kind = .Catalog,
			page = request.page,
		}
		if state == 0 {result.error = .Transport} else {
			result.catalog.query = strings.clone(request.text)
			if state == 2 {
				append(
					&result.catalog.videos,
					model.Video {
						id = strings.clone("DN953UW8iJ8"),
						title = strings.clone("Linus Tech Tips · local search check"),
						channel = strings.clone("Linus Tech Tips"),
						duration_ms = 100000,
						duration_label = model.time_label(100000),
					},
				)
			}
		}
		chan.send(network_results, result)
		poll_network(renderer)
		assert(!search_loading && browsing && running)
		name := state == 0 ? "search-error" : state == 1 ? "search-empty" : "search-results"
		snapshot(renderer, surface, name)
		assert(state == 0 ? notice != "" : notice == "")
		assert(len(catalog.videos) == (state == 2 ? 1 : 0))
		if state < 2 {key(sdl.K_TAB)}
	}
	// Notifications float above the cards and expire without clearing error state.
	card := clay.GetElementData(clay.ID("video", 0)).boundingBox
	show_notice("Could not save to Watch later")
	snapshot(renderer, surface, "toast")
	toast := clay.GetElementData(clay.ID("toast"))
	assert(toast.found && toast.boundingBox.x >= 0 && toast.boundingBox.y >= 0)
	assert(toast.boundingBox.x + toast.boundingBox.width <= view_width)
	assert(toast.boundingBox.y + toast.boundingBox.height <= view_height)
	assert(clay.GetElementData(clay.ID("video", 0)).boundingBox == card)
	expire_toast(toast_until)
	assert(render(renderer))
	assert(!clay.GetElementData(clay.ID("toast")).found && notice != "")
	notice = ""

	// History uses the same authenticated browse and continuation path as other feeds.
	saved_signed_in := signed_in
	defer {signed_in = saved_signed_in}
	signed_in = true
	activate_navigation(.History)
	history_request, history_ready := chan.try_recv(network_requests)
	assert(history_ready && history_request.kind == .Browse && history_request.text == "FEhistory")
	free_network_request(&history_request)
	activate_navigation(.History)
	_, duplicate_history := chan.try_recv(network_requests)
	assert(!duplicate_history, "reselecting a loading section must not restart its request")
	chan.send(
		network_results,
		Network_Result {
			kind = .Catalog,
			page = page,
			catalog = {continuation = strings.clone("history-next-page")},
		},
	)
	poll_network(renderer)
	activate_navigation(.History)
	_, duplicate_history = chan.try_recv(network_requests)
	assert(!duplicate_history, "reselecting the current section must keep its page")
	load_more()
	history_request, history_ready = chan.try_recv(network_requests)
	assert(
		history_ready &&
		history_request.text == "FEhistory" &&
		history_request.continuation == "history-next-page",
	)
	free_network_request(&history_request)
	chan.send(network_results, Network_Result{kind = .Catalog, page = page, error = .Transport})
	poll_network(renderer)
	activate_navigation(.History)
	history_request, history_ready = chan.try_recv(network_requests)
	assert(
		history_ready && history_request.text == "FEhistory",
		"a failed section must remain retryable",
	)
	free_network_request(&history_request)
	start_browse("UC-example")
	history_request, history_ready = chan.try_recv(network_requests)
	assert(history_ready && history_request.text == "UC-example")
	free_network_request(&history_request)
	activate_navigation(.History)
	history_request, history_ready = chan.try_recv(network_requests)
	assert(
		history_ready && history_request.text == "FEhistory",
		"the section icon must return from a nested page",
	)
	free_network_request(&history_request)
}
