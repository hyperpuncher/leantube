package main

import clay "../vendor/clay"
import "./model"
import "core:strings"
import sdl "vendor:sdl3"

check_channel_ui :: proc(renderer: ^sdl.Renderer, surface: ^sdl.Surface) {
	saved_channel, saved_avatar := catalog.channel, channel_avatar
	saved_selected, saved_rail, saved_focus, saved_cursor :=
		selected, rail_focus, channel_focus, channel_cursor
	catalog.channel = {
		id    = strings.clone("UC-example"),
		title = strings.clone("Linus Tech Tips"),
		meta  = strings.clone("@LinusTechTips · 16.9M subscribers · 7.9K videos"),
	}
	channel_avatar = load_texture(renderer, "tests/ui/cover.webp")
	defer {
		model.channel_destroy(&catalog.channel)
		sdl.DestroyTexture(channel_avatar)
		catalog.channel, channel_avatar = saved_channel, saved_avatar
		selected, rail_focus, channel_focus, channel_cursor =
			saved_selected, saved_rail, saved_focus, saved_cursor
	}
	for label, i in ([]string{"Videos", "Live", "Playlists"}) {
		append(
			&catalog.channel.tabs,
			model.Channel_Option{label = strings.clone(label), selected = i == 0},
		)
	}
	for label, i in ([]string{"Newest", "Popular", "Oldest"}) {
		append(
			&catalog.channel.sorts,
			model.Channel_Option{label = strings.clone(label), selected = i == 0},
		)
	}
	selected, rail_focus, channel_focus, channel_cursor = 0, false, false, 0
	library_focus_pending = true
	snapshot(renderer, surface, "channel")
	header := clay.GetElementData(clay.ID("channel-header"))
	grid := clay.GetElementData(clay.ID("library-scroll"))
	assert(header.found && grid.found)
	assert(header.boundingBox.y + header.boundingBox.height <= grid.boundingBox.y)
	for i in 0 ..< 6 {
		button := clay.GetElementData(clay.ID("channel-option", u32(i)))
		assert(button.found && button.boundingBox.width > 0)
		assert(
			button.boundingBox.x + button.boundingBox.width <= view_width,
			"channel controls must fit even in the narrow layout",
		)
	}
	key(sdl.K_UP)
	assert(channel_focus && !can_press_card(), "up from the first row must focus channel controls")
	for _ in 0 ..< 5 {key(sdl.K_RIGHT)}
	assert(channel_cursor == 5)
	snapshot(renderer, surface, "channel-focused")
	focused := clay.GetElementData(clay.ID("channel-option", 5)).boundingBox
	red, green, blue: u8
	assert(
		sdl.ReadSurfacePixel(
			surface,
			i32(focused.x + focused.width / 2),
			i32(focused.y + scaled(8)),
			&red,
			&green,
			&blue,
			nil,
		),
	)
	assert(
		red == u8(COLOR_ACCENT[0]) && green == u8(COLOR_ACCENT[1]) && blue == u8(COLOR_ACCENT[2]),
		"remote focus must be visible on the active channel control",
	)
	key(sdl.K_DOWN)
	assert(
		!channel_focus && selected == 0 && can_press_card(),
		"down must return focus to the cards",
	)
}
