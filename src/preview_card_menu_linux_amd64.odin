package main

import clay "../vendor/clay"
import "./model"
import sdl "vendor:sdl3"

check_card_menu_ui :: proc(renderer: ^sdl.Renderer, surface: ^sdl.Surface) {
	// This fixture has no usable mutation payloads. It only checks real layout,
	// focus, and dismissal through the same popup used on the TV.
	saved_actions := catalog.videos[selected].actions
	catalog.videos[selected].actions = nil
	defer {
		close_card_menu()
		model.card_actions_destroy(&catalog.videos[selected].actions)
		catalog.videos[selected].actions = saved_actions
	}
	for action in ([]model.Card_Action{{kind = .Edit_Playlist, label = "Save to Watch later", target = "WL"}, {kind = .Playlists, label = "Save to playlist"}, {kind = .Browse, label = "Go to channel"}, {kind = .Feedback, label = "Not interested"}}) {
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
