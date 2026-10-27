#+test
package main

import "./model"
import "core:strings"
import "core:testing"
import sdl "vendor:sdl3"

@(test)
card_hold_opens_actions_without_also_playing_on_release :: proc(t: ^testing.T) {
	saved_catalog, saved_selected := catalog, selected
	saved_browsing, saved_loaded, saved_paused := browsing, loaded, paused
	saved_rail, saved_search := rail_focus, search_editing
	saved_account, saved_login, saved_page := account_menu, login_screen, page
	saved_timeline := timeline
	catalog = {}
	defer {
		close_card_menu()
		model.catalog_destroy(&catalog)
		catalog, selected = saved_catalog, saved_selected
		browsing, loaded, paused = saved_browsing, saved_loaded, saved_paused
		rail_focus, search_editing = saved_rail, saved_search
		account_menu, login_screen, page = saved_account, saved_login, saved_page
		timeline = saved_timeline
	}
	append(
		&catalog.videos,
		model.Video{id = strings.clone("DN953UW8iJ8"), actions = make([dynamic]model.Card_Action)},
	)
	append(
		&catalog.videos[0].actions,
		model.Card_Action{kind = .Browse, label = strings.clone("Go to channel")},
	)
	browsing, loaded, selected = true, false, 0
	rail_focus, search_editing, account_menu, login_screen = false, false, false, false

	// Repeated OK events must not activate a row in the newly opened popup.
	begin_card_press(false, 1000)
	poll_card_press(1000 + CARD_HOLD_MS - 1)
	testing.expect(t, !card_menu && !loaded)
	poll_card_press(1000 + CARD_HOLD_MS)
	testing.expect(t, card_menu && !loaded)
	event: sdl.Event
	event.type = .KEY_DOWN
	event.key.key = sdl.K_RETURN
	event.key.repeat = true
	handle_event(nil, event)
	finish_card_press(false, 2000)
	testing.expect(t, card_menu && !loaded)
	close_card_menu()

	// A fast pointer click is deferred until release and opens the video once.
	begin_card_press(true, 3000)
	testing.expect(t, !loaded)
	finish_card_press(false, 3010)
	testing.expect(t, card_press.active && !loaded)
	finish_card_press(true, 3100)
	testing.expect(t, loaded && !browsing && !card_menu)

	// A release after a page change must not open an unrelated replacement card.
	browsing, loaded = true, false
	begin_card_press(false, 4000)
	page += 1
	finish_card_press(false, 4100)
	testing.expect(t, !loaded && !card_menu)

	// If release arrives before the next timer tick, it still counts as a hold.
	begin_card_press(false, 5000)
	finish_card_press(false, 5000 + CARD_HOLD_MS)
	testing.expect(t, card_menu && !loaded)
}
