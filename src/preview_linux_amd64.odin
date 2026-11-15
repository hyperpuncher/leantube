package main

import clay "../vendor/clay"
import "./model"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:sync/chan"
import sdl "vendor:sdl3"

UI_TEST :: #config(UI_TEST, false)
UI_SCREENSHOTS :: #config(UI_SCREENSHOTS, false)

save_snapshot :: proc(surface: ^sdl.Surface, name: string) {
	when UI_SCREENSHOTS {
		path := fmt.caprintf("build/ui-test/%s-%s.png", os.args[1], name)
		defer delete(path)
		assert(sdl.SavePNG(surface, path), string(sdl.GetError()))
	}
}

snapshot :: proc(renderer: ^sdl.Renderer, surface: ^sdl.Surface, name: string) {
	assert(render(renderer), string(sdl.GetError()))
	save_snapshot(surface, name)
}

main :: proc() {
	app_directory = "app"
	auth_directory = "build/dev"
	window: ^sdl.Window
	surface: ^sdl.Surface
	renderer: ^sdl.Renderer
	defer {
		if renderer != nil {sdl.DestroyRenderer(renderer)}
		if surface != nil {sdl.DestroySurface(surface)}
		if window != nil {sdl.DestroyWindow(window)}
		sdl.Quit()
	}
	when !UI_TEST {
		assert(sdl.SetHintWithPriority(sdl.HINT_VIDEO_DRIVER, "wayland", .OVERRIDE))
		assert(sdl.SetHint(sdl.HINT_RENDER_DRIVER, "opengles2"))
		assert(sdl.Init({.VIDEO}), string(sdl.GetError()))
		assert(string(sdl.GetCurrentVideoDriver()) == "wayland")
		assert(
			sdl.CreateWindowAndRenderer(
				"LeanTube · local UI preview (no playback)",
				1280,
				720,
				{.RESIZABLE, .HIGH_PIXEL_DENSITY},
				&window,
				&renderer,
			),
			string(sdl.GetError()),
		)
	} else {
		width, height: i32 = 1920, 1080
		if os.args[1] == "720p" {width, height = 1280, 720}
		if os.args[1] == "1440p" {width, height = 2560, 1440}
		if os.args[1] == "4k" {width, height, ui_scale = 3840, 2160, 2}
		surface = sdl.CreateSurface(width, height, .RGBA32)
		assert(surface != nil)
		renderer = sdl.CreateSoftwareRenderer(surface)
		assert(renderer != nil)
	}
	assert(sdl.SetRenderDrawBlendMode(renderer, sdl.BLENDMODE_BLEND))
	when UI_TEST {check_rounded_edges(renderer, surface)}
	assert(open_text(renderer), string(sdl.GetError()))
	defer close_text()
	defer close_fade()
	defer close_icons()
	defer clear_catalog()
	defer {
		close_login_screen()
		stop_network(); close_search(); delete(sponsor_segments)
		clear_browse_history()
		delete(browse_id); delete(browse_params); delete(browse_filter)
	}
	when UI_TEST {
		titles := [?]string {
			"FLOW",
			"Big Buck Bunny 60fps 4K - Official Blender Foundation Short Film",
			"café and a longer title for layout checks",
			"Spring - Blender Open Movie 🐶 🚀 🇺🇦",
		}
		count := 24
		// Test an incomplete final row.
		if UI_TEST && os.args[1] == "1440p" {count -= 1}
		resize(&textures, count)
		resize(&card_avatars, count)
		catalog.query = fmt.aprintf("local scrolling test · %d videos", count)
		for i in 0 ..< count {
			append(
				&catalog.videos,
				model.Video {
					title = fmt.aprintf("video %02d · %s", i + 1, titles[i % len(titles)]),
					cover_index = i,
					id = i == 0 ? strings.clone("DN953UW8iJ8") : "",
					duration_ms = 100000,
					watched_percent = i == 0 ? 35 : i == 1 ? 100 : 0,
					channel = i == 0 ? strings.clone("Theo - t3․gg") : fmt.aprintf("channel %02d", i + 1),
					duration_label = model.time_label(100000),
				},
			)
			append(
				&catalog.videos[i].actions,
				model.Card_Action {
					kind = .Browse,
					label = strings.clone("Go to channel"),
					target = strings.clone("UC-example"),
				},
			)
			if i != 2 {card_avatars[i] = load_texture(renderer, "tests/ui/cover.webp")}
			if UI_TEST && i == 1 {
				textures[i] = load_texture(renderer, "tests/ui/cover.jpg")
				assert(textures[i] != nil)
				continue
			}
			if UI_TEST && i == 2 {continue} 	// A missing cover must retain its grid slot.
			shade := u8(80 + i * 6)
			pixels: [16 * 9][4]u8
			for &pixel in pixels {pixel = {shade, shade, shade, 255}}
			textures[i] = sdl.CreateTexture(renderer, .RGBA32, .STATIC, 16, 9)
			assert(textures[i] != nil)
			assert(sdl.UpdateTexture(textures[i], nil, raw_data(pixels[:]), 16 * 4))
			assert(sdl.SetTextureBlendMode(textures[i], sdl.BLENDMODE_BLEND))
		}
	}
	memory := open_clay()
	defer delete(memory)
	when UI_TEST {check_layout(renderer, surface)} else {
		if start_network() {
			activate_navigation(signed_in ? .Subscriptions : .Home)
		} else {
			show_notice("Network unavailable")
		}
		run_dev(renderer)
	}
}

check_layout :: proc(renderer: ^sdl.Renderer, surface: ^sdl.Surface) {
	snapshot(renderer, surface, "start")
	// Keyboard input must clear the old mouse hover, not leave two cards lit.
	hovered_card := clay.GetElementData(clay.ID("video", 0)).boundingBox
	clay.SetPointerState(
		{hovered_card.x + hovered_card.width / 2, hovered_card.y + scaled(8)},
		false,
	)
	assert(clay.PointerOver(clay.ID("video", 0)))
	event: sdl.Event
	event.type = .KEY_DOWN
	event.key.key = sdl.K_RIGHT
	handle_event(renderer, event)
	assert(selected == 1)
	assert(!clay.PointerOver(clay.ID("video", 0)), "keyboard input must clear mouse hover")
	key(sdl.K_LEFT)
	assert(!clay.GetElementData(clay.ID("search")).found)
	key(sdl.K_AC_BACK)
	assert(running && browsing, "short back at the root must not close the app")
	check_watch_later_ui(renderer, surface)
	check_text_fitting()
	red, green, blue: u8
	assert(sdl.ReadSurfacePixel(surface, 0, 0, &red, &green, &blue, nil))
	assert(red == 0 && green == 0 && blue == 0)
	rail := clay.GetElementData(clay.ID("navigation")).boundingBox
	assert(rail.x == 0 && rail.y == 0 && rail.height == view_height)
	previous_bottom: f32
	for item in Navigation {
		box := clay.GetElementData(clay.ID("navigation-item", u32(item))).boundingBox
		assert(box.width > 0 && box.y >= previous_bottom)
		previous_bottom = box.y + box.height
	}
	assert(previous_bottom <= view_height)
	key(sdl.K_LEFT)
	assert(rail_focus && selected == 0)
	snapshot(renderer, surface, "rail-focused")
	search_tooltip := clay.GetElementData(clay.ID("navigation-tooltip", u32(Navigation.Search)))
	assert(search_tooltip.found)
	// The shadow fades outside the popup over the first thumbnail, not its layout box.
	shadow: [2]u8
	for distance, i in ([2]f32{3, 9}) {
		box := search_tooltip.boundingBox
		assert(
			sdl.ReadSurfacePixel(
				surface,
				i32(box.x + box.width - scaled(8)),
				i32(box.y + box.height + scaled(distance)),
				&shadow[i],
				nil,
				nil,
				nil,
			),
		)
	}
	assert(
		shadow[0] > 0 && shadow[0] < shadow[1] && shadow[1] < 80,
		"popup shadow must fade over the thumbnail",
	)
	grid_before_tooltip := clay.GetElementData(clay.ID("video", 0)).boundingBox
	rail_cursor = .History
	snapshot(renderer, surface, "rail-history")
	history := clay.GetElementData(clay.ID("navigation-item", u32(Navigation.History))).boundingBox
	tooltip := clay.GetElementData(clay.ID("navigation-tooltip", u32(Navigation.History)))
	assert(tooltip.found && tooltip.boundingBox.x > history.x + history.width)
	assert(clay.GetElementData(clay.ID("video", 0)).boundingBox == grid_before_tooltip)
	assert(
		sdl.ReadSurfacePixel(
			surface,
			i32(tooltip.boundingBox.x + scaled(4)),
			i32(history.y + history.height / 2),
			&red,
			nil,
			nil,
			nil,
		),
	)
	assert(red == u8(COLOR_TEXT[0]), "the tooltip must draw above the library")
	key(sdl.K_RIGHT)
	assert(!rail_focus && selected == 0)
	assert(render(renderer))
	assert(!clay.GetElementData(clay.ID("navigation-tooltip", u32(Navigation.History))).found)
	clay.SetPointerState({history.x + history.width / 2, history.y + history.height / 2}, false)
	snapshot(renderer, surface, "rail-history-hover")
	assert(clay.GetElementData(clay.ID("navigation-tooltip", u32(Navigation.History))).found)
	clay.SetPointerState({-1, -1}, false)
	assert(render(renderer))
	assert(!clay.GetElementData(clay.ID("navigation-tooltip", u32(Navigation.History))).found)
	check_cover_fill(renderer, surface)
	assert(render(renderer))
	first := clay.GetElementData(clay.ID("video", 0)).boundingBox
	first_cover := clay.GetElementData(clay.ID("cover", 0)).boundingBox
	// Selection covers the caption area too, without an accent outline.
	assert(
		sdl.ReadSurfacePixel(
			surface,
			i32(first.x + scaled(24)),
			i32(first.y + first.height - scaled(6)),
			&red,
			&green,
			&blue,
			nil,
		),
	)
	assert(red == u8(COLOR_TEXT[0]) && green == u8(COLOR_TEXT[1]) && blue == u8(COLOR_TEXT[2]))
	for index in ([2]int{0, 2}) {
		avatar := clay.GetElementData(clay.ID("card-avatar", u32(index))).boundingBox
		assert(avatar.width == scaled(40))
		if avatar.y + avatar.height / 2 >= view_height {continue}
		assert(
			sdl.ReadSurfacePixel(
				surface,
				i32(avatar.x + avatar.width / 2),
				i32(avatar.y + avatar.height / 2),
				&red,
				&green,
				&blue,
				nil,
			),
		)
		if index ==
		   0 {assert(red > 240, "a placeholder must not cover a loaded avatar")} else {assert(red == u8(COLOR_SURFACE[0]))}
	}
	completed_cover := clay.GetElementData(clay.ID("cover", 1)).boundingBox
	// A full progress bar must leave the rounded corner clear.
	for offset, i in ([2]f32{1, scaled(24)}) {
		assert(
			sdl.ReadSurfacePixel(
				surface,
				i32(completed_cover.x + offset),
				i32(completed_cover.y + completed_cover.height - scaled(2)),
				&red,
				&green,
				&blue,
				nil,
			),
		)
		expected := i == 0 ? COLOR_BACKGROUND : COLOR_ACCENT
		assert(red == u8(expected[0]) && green == u8(expected[1]) && blue == u8(expected[2]))
	}
	assert(
		sdl.ReadSurfacePixel(
			surface,
			i32(first_cover.x + first_cover.width / 2),
			i32(first_cover.y + first_cover.height - scaled(2)),
			&red,
			&green,
			&blue,
			nil,
		),
	)
	assert(red == u8(COLOR_TRACK[0]) && green == u8(COLOR_TRACK[1]) && blue == u8(COLOR_TRACK[2]))
	assert(!clay.GetElementData(clay.ID("watched-progress", 2)).found)
	// Only rows near the viewport enter layout; the rest keep their space.
	metrics := grid_metrics()
	launched := 0
	for video, i in catalog.videos {
		card := clay.GetElementData(clay.ID("video", u32(i)))
		if !card.found {continue}
		launched += 1
		column := clay.GetElementData(clay.ID("video", u32(i % grid_columns)))
		assert(
			math.abs(card.boundingBox.width - first.width) < 0.1,
			"grid cards must have equal widths",
		)
		shape := card_shape(video)
		assert(
			math.abs(card.boundingBox.height - card_height(metrics, shape)) < 0.1,
			"a card must not reserve unused text lines",
		)
		last :=
			clay.GetElementData(clay.ID(shape.meta ? "card-meta" : "card-channel", u32(i))).boundingBox
		bottom := card.boundingBox.y + card.boundingBox.height
		assert(
			math.abs(bottom - (last.y + last.height) - metrics.padding) < 0.1,
			"a card must end at its padding, not with unused space",
		)
		assert(
			math.abs(card.boundingBox.x - column.boundingBox.x) < 0.1,
			"grid columns must align",
		)
		cover := clay.GetElementData(clay.ID("cover", u32(i))).boundingBox
		assert(math.abs(cover.width - first_cover.width) < 0.1)
		assert(math.abs(cover.height - first_cover.height) < 0.1)
		assert(math.abs(cover.width - cover.height * (16.0 / 9.0)) < 0.1)
	}
	assert(launched >= grid_columns * 2, "a full screen of rows must be laid out")
	assert(!clay.GetElementData(clay.ID("video", u32(len(catalog.videos) - 1))).found)
	// The chip pads a line box, so the digits themselves must still look centred.
	chip := clay.GetElementData(clay.ID("duration", 0)).boundingBox
	first_ink, last_ink := -1, -1
	for y in int(chip.y) ..< int(chip.y + chip.height) {
		ink, total: int
		for x in int(chip.x) ..< int(chip.x + chip.width) {
			r, g, b: u8
			if !sdl.ReadSurfacePixel(surface, i32(x), i32(y), &r, &g, &b, nil) {continue}
			brightness := int(r) + int(g) + int(b)
			total += brightness
			if brightness > 360 {ink += 1}
		}
		// Covers and the chip's own edges are full width; text rows are not.
		if ink > 0 && ink < int(chip.width * 0.9) && total / max(1, int(chip.width)) > 90 {
			if first_ink < 0 {first_ink = y}
			last_ink = y
		}
	}
	assert(first_ink >= 0 && last_ink > first_ink, "the duration chip must draw text")
	assert(
		math.abs((f32(first_ink) + f32(last_ink)) / 2 - (chip.y + chip.height / 2)) <= 1,
		"duration digits must look centred in their chip",
	)
	scroll_grid := clay.GetScrollContainerData(clay.ID("library-scroll"))
	rows := len(row_heights)
	assert(
		math.abs(scroll_grid.contentDimensions.height - row_offsets[rows]) < 1,
		"spacers must preserve the complete grid height",
	)
	initial_view := clay.GetElementData(clay.ID("library-scroll")).boundingBox
	assert(
		math.abs(initial_view.y + initial_view.height - view_height) < 0.1,
		"the library must reach the bottom edge",
	)
	assert(icon_pixels == i32(scaled(48)))
	if os.args[1] == "4k" {
		assert(view_width == 3840 && view_height == 2160)
		assert(text_sizes[.Body] == BASE_TEXT_SIZES[.Body] * 2)
	}
	if os.args[1] == "1440p" {assert(grid_columns == 4)}
	// Pagination must start before the final row, without moving the view or
	// replacing thumbnails when the texture arrays grow.
	network_requests, _ = chan.create(chan.Chan(Network_Request), 1, context.allocator)
	network_results, _ = chan.create(chan.Chan(Network_Result), 1, context.allocator)
	browse_id = strings.clone("FEsubscriptions")
	catalog.continuation = strings.clone("next-page")
	for direction in ([]int{1, -1}) {
		for step in 1 ..= 4 {
			key(direction > 0 ? sdl.K_DOWN : sdl.K_UP)
			scroll := clay.GetScrollContainerData(clay.ID("library-scroll"))
			before := scroll.scrollPosition^[1]
			viewport := clay.GetElementData(clay.ID("library-scroll")).boundingBox
			name := fmt.aprintf("%s-%d", direction > 0 ? "down" : "up", step)
			snapshot(renderer, surface, name)
			delete(name)
			after := clay.GetScrollContainerData(clay.ID("library-scroll")).scrollPosition^[1]
			fmt.printf(
				"%s %d: video %d, scroll %g -> %g\n",
				direction > 0 ? "down" : "up",
				step,
				selected + 1,
				before,
				after,
			)
			now := clay.GetElementData(clay.ID("video", u32(selected))).boundingBox
			assert(
				now.y >= viewport.y && now.y + now.height <= viewport.y + viewport.height,
				"keyboard selection must remain visible",
			)
			if direction < 0 {
				row := selected / grid_columns
				top := row_offsets[row]
				bottom := top + row_heights[row]
				if top >= -before && bottom <= -before + scroll.scrollContainerDimensions.height {
					assert(before == after, "moving to a fully visible row must not scroll")
				}
			}
		}
		if direction > 0 {
			if !search_loading {
				scroll := clay.GetScrollContainerData(clay.ID("library-scroll"))
				scroll.scrollPosition^[1] =
					-scroll.contentDimensions.height + scroll.scrollContainerDimensions.height * 2
				assert(render(renderer))
			}
			request, ready := chan.try_recv(network_requests)
			assert(ready && request.kind == .Browse && request.continuation == "next-page")
			assert(!loading_active(), "background pagination must not animate an unchanged grid")
			free_network_request(&request)
			assert(selected / grid_columns < (len(catalog.videos) - 1) / grid_columns)
			before := clay.GetScrollContainerData(clay.ID("library-scroll")).scrollPosition^[1]
			first_cover := len(catalog.videos)
			result := Network_Result {
				kind   = .Catalog,
				page   = page,
				append = true,
			}
			for i in 0 ..< 18 {
				append(
					&result.catalog.videos,
					model.Video {
						title = fmt.aprintf("next-page video %d", i),
						cover_index = first_cover + i,
						thumbnail_url = strings.clone("https://images.example/next-page"),
						duration_ms = 100000,
						duration_label = model.time_label(100000),
					},
				)
			}
			chan.send(network_results, result)
			poll_network(renderer)
			assert(len(image_loader.pending) == 18, "a new page must queue its covers")
			for image in image_loader.pending {assert(image.index >= first_cover)}
			clear_image_requests()
			assert(render(renderer))
			assert(
				clay.GetScrollContainerData(clay.ID("library-scroll")).scrollPosition^[1] ==
				before,
				"adding a page must not pull wheel scrolling back to the selection",
			)
		}
	}
	assert(!clay.GetElementData(clay.ID("load-more")).found)
	first_cover = clay.GetElementData(clay.ID("cover", 0)).boundingBox
	assert(
		sdl.ReadSurfacePixel(
			surface,
			i32(first_cover.x + first_cover.width / 2),
			i32(first_cover.y + first_cover.height / 2),
			&red,
			nil,
			nil,
			nil,
		),
	)
	assert(
		red == 80,
		"an earlier thumbnail must still be displayed after loading more and scrolling back up",
	)
	stop_network()
	delete(browse_id); browse_id = ""
	// A new display order must keep each fitted title with its card.
	last_index := len(catalog.videos) - 1
	catalog.videos[0], catalog.videos[last_index] = catalog.videos[last_index], catalog.videos[0]
	catalog_revision += 1
	assert(render(renderer))
	clay.BeginLayout()
	grid_layout()
	commands := clay.EndLayout(0)
	found_title := false
	for i in 0 ..< commands.length {
		command := clay.RenderCommandArray_Get(&commands, i)
		if command.commandType != .Text {continue}
		text := command.renderData.text.stringContents
		if string(text.chars[:text.length]) == catalog.videos[0].title {
			found_title = true
			assert(
				command.renderData.text.textColor == COLOR_BACKGROUND,
				"selected card text must be dark",
			)
		}
	}
	assert(found_title, "sorting must not attach another card's fitted title")
	catalog.videos[0], catalog.videos[last_index] = catalog.videos[last_index], catalog.videos[0]
	catalog_revision += 1
	// A width change still needs fresh fitting, even with no new cards.
	cached_title := strings.clone(card_labels[1].title)
	narrow := grid_metrics()
	narrow.text_width = scaled(80)
	labels_build(narrow)
	assert(card_labels[1].title != cached_title)
	delete(cached_title)
	labels_build(grid_metrics())
	assert(render(renderer))
	// The last card, wheel scrolling, and a round trip through the player must
	// use the same retained scroll state, without pulling focus to the pointer.
	selected = len(catalog.videos) - 1
	library_focus_pending = true
	snapshot(renderer, surface, "last")
	viewport := clay.GetElementData(clay.ID("library-scroll")).boundingBox
	last := clay.GetElementData(clay.ID("video", u32(selected))).boundingBox
	assert(last.y >= viewport.y && last.y + last.height <= viewport.y + viewport.height)
	scroll := clay.GetScrollContainerData(clay.ID("library-scroll"))
	before_player := scroll.scrollPosition^[1]
	key(sdl.K_RETURN)
	assert(!browsing && loaded && paused)
	player_channel_id = strings.clone("UC-example")
	player_channel_avatar = load_texture(renderer, "tests/ui/cover.webp")
	assert(player_channel_avatar != nil)
	check_sponsor_timeline(renderer, surface)
	check_buffered_timeline(renderer, surface)
	// A pending seek must move the knob and the time before the decoder replies.
	knob_before := clay.GetElementData(clay.ID("timeline-knob")).boundingBox
	timeline.seek_target_ms = duration_ms / 2
	assert(render(renderer, 10))
	knob_target := clay.GetElementData(clay.ID("timeline-knob")).boundingBox
	assert(knob_target.x > knob_before.x + scaled(10), "the knob must follow a pending seek")
	model.seek_done(&timeline)
	assert(timeline.position_ms == duration_ms / 2)
	snapshot(renderer, surface, "player-paused")
	// Sample the fill outside each icon or avatar, before and after hover.
	hover_ids := [4]string{"pause", "slower", "faster", "player-channel"}
	background: [4]u8
	for id, i in hover_ids {
		box := clay.GetElementData(clay.ID(id)).boundingBox
		assert(
			sdl.ReadSurfacePixel(
				surface,
				i32(box.x + box.width / 2),
				i32(box.y + scaled(4)),
				&background[i],
				nil,
				nil,
				nil,
			),
		)
	}
	for id, i in hover_ids {
		box := clay.GetElementData(clay.ID(id)).boundingBox
		clay.SetPointerState({box.x + box.width / 2, box.y + box.height / 2}, false)
		name := fmt.aprintf("player-hover-%s", id)
		snapshot(renderer, surface, name)
		delete(name)
		assert(
			sdl.ReadSurfacePixel(
				surface,
				i32(box.x + box.width / 2),
				i32(box.y + scaled(4)),
				&red,
				nil,
				nil,
				nil,
			),
		)
		color := id == "player-channel" ? COLOR_TRACK : COLOR_HOVER
		alpha := COLOR_BADGE[3] / 255
		expected := color[0] * alpha + f32(background[i]) * (1 - alpha)
		assert(
			math.abs(f32(red) - expected) <= 2,
			"player hover must blend with the picture behind it",
		)
	}
	clay.SetPointerState({-1, -1}, false)
	assert(render(renderer))
	panel := clay.GetElementData(clay.ID("controls")).boundingBox
	play_button := clay.GetElementData(clay.ID("pause")).boundingBox
	key(sdl.K_RETURN)
	assert(!paused)
	snapshot(renderer, surface, "player")
	assert(play_button == clay.GetElementData(clay.ID("pause")).boundingBox)
	assert(panel.y + panel.height == view_height)
	key(sdl.K_AC_BACK)
	assert(return_to_grid)
	stop_playback()
	assert(browsing && !return_to_grid)
	snapshot(renderer, surface, "restored")
	scroll = clay.GetScrollContainerData(clay.ID("library-scroll"))
	assert(
		scroll.scrollPosition^[1] == before_player,
		"returning from the player must preserve the view",
	)
	clay.SetPointerState({scaled(200), scaled(300)}, false)
	assert(render(renderer, 10))
	scroll = clay.GetScrollContainerData(clay.ID("library-scroll"))
	assert(scroll.scrollPosition^[1] > before_player, "wheel scrolling must move the view")
	assert(selected == len(catalog.videos) - 1)
	assert(running)
	check_card_menu_ui(renderer, surface)
	check_channel_ui(renderer, surface)
	check_account_ui(renderer, surface)
	check_search_flow(renderer, surface)
	check_login_ui(renderer, surface)
	// Check both optimized scans at the end of a large feed.
	{
		clear_catalog()
		count :: 1000
		resize(&textures, count)
		resize(&card_avatars, count)
		for i in 0 ..< count {
			append(
				&catalog.videos,
				model.Video {
					id = fmt.aprintf("video%06d", i),
					title = strings.clone("Large feed card"),
					duration_label = strings.clone("10:00"),
					cover_index = i,
				},
			)
		}
		last := count - 1
		textures[last] = load_texture(renderer, "tests/ui/cover.webp")
		assert(textures[last] != nil)
		selected, library_focus_pending = last, true
		assert(render(renderer))
		box := clay.GetElementData(clay.ID("video", u32(last))).boundingBox
		selected = 0
		controls_pointer(renderer, box.x + box.width / 2, box.y + scaled(32), false, false)
		assert(selected == last, "pointer selection must reach the final visible card")
		snapshot(renderer, surface, "large-grid")
		retained := take_image_texture(image_key(catalog.videos[last].id, 0))
		assert(retained == textures[last], "the final visible thumbnail must be retained")
		sdl.DestroyTexture(retained)
	}
	fmt.printf("%s: UI checks passed\n", os.args[1])
}
