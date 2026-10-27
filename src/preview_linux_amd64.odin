package main

import clay "../vendor/clay"
import "./model"
import "core:c"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:sync/chan"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

UI_TEST :: #config(UI_TEST, false)

snapshot :: proc(renderer: ^sdl.Renderer, surface: ^sdl.Surface, name: string) {
	assert(render(renderer), string(sdl.GetError()))
	path := fmt.caprintf("build/ui-test/%s-%s.png", os.args[1], name)
	defer delete(path)
	assert(sdl.SavePNG(surface, path), string(sdl.GetError()))
}

check_rounded_edges :: proc(renderer: ^sdl.Renderer, surface: ^sdl.Surface) {
	// An original opaque WebP must retain its dimensions and get smooth edges.
	texture := load_texture(renderer, "tests/ui/cover.webp")
	assert(texture != nil)
	defer sdl.DestroyTexture(texture)
	width, height: f32
	assert(sdl.GetTextureSize(texture, &width, &height))
	assert(width == 101 && height == 57, "WebP decoding must retain the source dimensions")
	assert(set_color(renderer, {0, 0, 0, 255}) && sdl.RenderClear(renderer))
	for i in 0 ..< 2 {
		x := f32(16 + i * 96)
		assert(
			rounded_shape(
				renderer,
				{x, 16, 64, 64},
				clay.CornerRadiusAll(16),
				{255, 255, 255, 255},
				i == 0 ? nil : texture,
			),
		)
	}
	assert(sdl.RenderPresent(renderer))
	for i in 0 ..< 2 {
		partial := 0
		for y in 16 ..< 32 {
			for x in 16 ..< 32 {
				red: u8
				assert(sdl.ReadSurfacePixel(surface, i32(x + i * 96), i32(y), &red, nil, nil, nil))
				if red > 0 && red < 255 {partial += 1}
			}
		}
		assert(partial > 8, "rounded fills and opaque images must have antialiased edges")
	}
	assert(sdl.SavePNG(surface, "build/ui-test/rounded-edges.png"))
}

// A 4:3 JPEG with baked-in bars must fill a 16:9 frame in both render paths.
check_cover_fill :: proc(renderer: ^sdl.Renderer, surface: ^sdl.Surface) {
	texture := load_texture(renderer, "tests/ui/cover.jpg")
	assert(texture != nil)
	defer sdl.DestroyTexture(texture)
	width, height: f32
	assert(sdl.GetTextureSize(texture, &width, &height))
	assert(width == 160 && height == 120, "JPEG decoding must retain the source dimensions")
	commands: [2]clay.RenderCommand
	for &command, i in commands {
		command.commandType = .Image
		command.boundingBox = {f32(16 + i * 200), 16, 160, 90}
		command.renderData.image.imageData = rawptr(texture)
		if i == 1 {command.renderData.image.cornerRadius = clay.CornerRadiusAll(12)}
	}
	assert(set_color(renderer, {0, 0, 0, 255}) && sdl.RenderClear(renderer))
	assert(
		render_commands(
			renderer,
			{capacity = 2, length = 2, internalArray = raw_data(commands[:])},
		),
	)
	for i in 0 ..< 2 {
		for point in ([][2]i32{{80, 2}, {80, 87}, {2, 45}, {157, 45}}) {
			red: u8
			assert(
				sdl.ReadSurfacePixel(
					surface,
					i32(16 + i * 200) + point[0],
					16 + point[1],
					&red,
					nil,
					nil,
					nil,
				),
			)
			assert(red > 240, "center-crop must remove the baked-in bars without side gaps")
		}
	}
	assert(sdl.SavePNG(surface, "build/ui-test/cover-fill.png"))
}

main :: proc() {
	app_directory = "app"
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
		if os.args[1] == "1440p" {width, height = 2560, 1440}
		if os.args[1] == "4k" {width, height, ui_scale = 3840, 2160, 2}
		if os.args[1] == "narrow" {width = 960}
		surface = sdl.CreateSurface(width, height, .RGBA32)
		assert(surface != nil)
		renderer = sdl.CreateSoftwareRenderer(surface)
		assert(renderer != nil)
	}
	assert(sdl.SetRenderDrawBlendMode(renderer, sdl.BLENDMODE_BLEND))
	when UI_TEST {check_rounded_edges(renderer, surface)}
	assert(open_text(renderer), string(sdl.GetError()))
	defer close_text()
	defer close_icons()
	defer clear_catalog()
	defer {stop_network(); delete(search_text); delete(sponsor_segments)}
	when UI_TEST {
		titles := [?]string {
			"FLOW",
			"Big Buck Bunny 60fps 4K - Official Blender Foundation Short Film",
			"café and a longer title for layout checks",
			"Spring - Blender Open Movie",
		}
		count := 24
		// Test an incomplete final row.
		if UI_TEST && os.args[1] == "1440p" {count -= 1}
		resize(&textures, count)
		catalog.query = fmt.aprintf("local scrolling test · %d videos", count)
		for i in 0 ..< count {
			append(
				&catalog.videos,
				model.Video {
					title = fmt.aprintf("video %02d · %s", i + 1, titles[i % len(titles)]),
					duration_ms = 100000,
					channel = fmt.aprintf("channel %02d", i + 1),
					duration_label = model.time_label(100000),
				},
			)
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
	clay.SetMaxElementCount(8192)
	clay.SetMaxMeasureTextCacheWordCount(32768)
	memory := make([]u8, int(clay.MinMemorySize()))
	defer delete(memory)
	clay.Initialize(
		clay.CreateArenaWithCapacityAndMemory(uint(len(memory)), raw_data(memory)),
		{},
		{handler = clay_error},
	)
	clay.SetMeasureTextFunction(measure_text, nil)
	when UI_TEST {check_layout(renderer, surface)} else {
		if start_network() {
			activate_navigation(signed_in ? .Subscriptions : .Home)
		} else {
			notice = "network is unavailable"
		}
		run_dev(renderer)
	}
}

check_layout :: proc(renderer: ^sdl.Renderer, surface: ^sdl.Surface) {
	snapshot(renderer, surface, "start")
	assert(!clay.GetElementData(clay.ID("search")).found)
	// Use real font measurements, including UTF-8 and an explicit final line.
	for sample in ([]string{"short", "café café café café café café", "a long channel name that must end with an ellipsis"}) {
		fit, owned := fit_text(fonts[.Small], sample, 160)
		defer if owned {delete(fit)}
		width: i32
		assert(ttf.GetStringSize(fonts[.Small], raw_data(fit), len(fit), &width, nil))
		assert(width <= 160)
		if owned {assert(strings.has_suffix(fit, "…"))} else {assert(fit == sample)}
	}
	continued, owned := fit_text(fonts[.Small], "short", 160, true)
	defer if owned {delete(continued)}
	assert(strings.has_suffix(continued, "…"))
	too_narrow, _ := fit_text(fonts[.Small], "text", 1)
	assert(too_narrow == "")
	// A wrapped title is fitted to two lines and keeps the trailing ellipsis.
	wrapped, wrapped_owned := fit_wrapped(
		fonts[.Small],
		"a very long video title that keeps going well past two lines of text for the card",
		400,
		2,
	)
	defer if wrapped_owned {delete(wrapped)}
	assert(strings.has_suffix(wrapped, "…"))
	line_height := c.int(ttf.GetFontHeight(fonts[.Small]))
	probe := ttf.CreateText(text_engine, fonts[.Small], raw_data(wrapped), c.size_t(len(wrapped)))
	assert(probe != nil)
	assert(ttf.SetTextWrapWidth(probe, 400))
	wrapped_width, wrapped_height: c.int
	assert(ttf.GetTextSize(probe, &wrapped_width, &wrapped_height))
	ttf.DestroyText(probe)
	assert(wrapped_width <= 400)
	assert(wrapped_height <= 2 * line_height, "a fitted title must wrap to two lines at most")
	fits, fits_owned := fit_wrapped(fonts[.Small], "short title", 400, 2)
	assert(!fits_owned && fits == "short title")
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
	key(sdl.K_RIGHT)
	assert(!rail_focus && selected == 0)
	check_cover_fill(renderer, surface)
	first := clay.GetElementData(clay.ID("video", 0)).boundingBox
	first_cover := clay.GetElementData(clay.ID("cover", 0)).boundingBox
	for _, i in catalog.videos {
		card := clay.GetElementData(clay.ID("video", u32(i))).boundingBox
		column := clay.GetElementData(clay.ID("video", u32(i % grid_columns))).boundingBox
		assert(math.abs(card.width - first.width) < 0.1, "all grid cards must have equal widths")
		assert(math.abs(card.x - column.x) < 0.1, "grid columns must align across rows")
		cover := clay.GetElementData(clay.ID("cover", u32(i))).boundingBox
		assert(math.abs(cover.width - first_cover.width) < 0.1)
		assert(math.abs(cover.height - first_cover.height) < 0.1)
		assert(math.abs(cover.width - cover.height * (16.0 / 9.0)) < 0.1)
	}
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
	if os.args[1] == "narrow" {assert(grid_columns == 1)}
	for direction in ([]int{1, -1}) {
		for step in 1 ..= 4 {
			key(direction > 0 ? sdl.K_DOWN : sdl.K_UP)
			before := clay.GetScrollContainerData(clay.ID("library-scroll")).scrollPosition^[1]
			item := clay.GetElementData(clay.ID("video", u32(selected))).boundingBox
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
			if direction < 0 &&
			   item.y >= viewport.y &&
			   item.y + item.height <= viewport.y + viewport.height {
				assert(before == after, "moving to a visible row must not scroll")
			}
		}
	}
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
	check_sponsor_timeline(renderer, surface)
	// A pending seek must move the knob and the time before the decoder replies.
	knob_before := clay.GetElementData(clay.ID("timeline-knob")).boundingBox
	timeline.seek_target_ms = duration_ms / 2
	assert(render(renderer, 10))
	knob_target := clay.GetElementData(clay.ID("timeline-knob")).boundingBox
	assert(knob_target.x > knob_before.x + scaled(10), "the knob must follow a pending seek")
	model.seek_done(&timeline)
	assert(timeline.position_ms == duration_ms / 2)
	snapshot(renderer, surface, "player-seek")
	snapshot(renderer, surface, "player-paused")
	panel := clay.GetElementData(clay.ID("controls")).boundingBox
	play_button := clay.GetElementData(clay.ID("pause")).boundingBox
	key(sdl.K_RETURN)
	assert(!paused)
	snapshot(renderer, surface, "player")
	assert(play_button == clay.GetElementData(clay.ID("pause")).boundingBox)
	assert(COLOR_PANEL[3] > 0 && COLOR_PANEL[3] < 255)
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
	check_account_ui(renderer, surface)
	check_search_flow(renderer, surface)
	fmt.println(
		"scrolling, player return, search states, and image edges passed; screenshots: build/ui-test",
	)
}

check_account_ui :: proc(renderer: ^sdl.Renderer, surface: ^sdl.Surface) {
	// Local fixtures only. Never load or modify a real account file here.
	saved_accounts, saved_active := auth_accounts, auth_active
	saved_signed_in, saved_avatar := signed_in, account_avatar
	auth_accounts = make([dynamic]Auth_Token)
	append(&auth_accounts, Auth_Token{name = "Alice"}, Auth_Token{name = "Bob"})
	auth_active = 0
	signed_in = true
	account_avatar = load_texture(renderer, "tests/ui/cover.webp")
	assert(account_avatar != nil)
	defer {
		sdl.DestroyTexture(account_avatar)
		delete(auth_accounts)
		auth_accounts, auth_active = saved_accounts, saved_active
		signed_in, account_avatar = saved_signed_in, saved_avatar
		account_menu = false
	}
	snapshot(renderer, surface, "account-avatar")
	avatar := clay.GetElementData(clay.ID("account-avatar"))
	assert(avatar.found && avatar.boundingBox.width == avatar.boundingBox.height)
	assert(!clay.GetElementData(clay.ID("sign-out")).found)
	account_menu = true
	snapshot(renderer, surface, "users")
	assert(clay.GetElementData(clay.ID("account-row", 0)).found)
	assert(clay.GetElementData(clay.ID("account-row", 1)).found)
	assert(clay.GetElementData(clay.ID("add-account")).found)
	assert(clay.GetElementData(clay.ID("sign-out")).found)
	account_menu_selected = 0
	key(sdl.K_DOWN)
	assert(account_menu_selected == 1)
	key(sdl.K_UP)
	assert(account_menu_selected == 0)
	key(sdl.K_AC_BACK)
	assert(!account_menu && running)
}

check_search_flow :: proc(renderer: ^sdl.Renderer, surface: ^sdl.Surface) {
	network_requests, _ = chan.create(chan.Chan(Network_Request), 1, context.allocator)
	network_results, _ = chan.create(chan.Chan(Network_Result), 2, context.allocator)
	defer stop_network()
	selected = 0
	key(sdl.K_TAB)
	assert(search_editing)
	event: sdl.Event
	event.type = .TEXT_INPUT
	event.text.text = "café"
	handle_event(renderer, event)
	assert(string(search_text[:]) == "café")
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
	for state in 0 ..< 3 {
		key(sdl.K_RETURN)
		assert(search_loading && !search_editing && len(catalog.videos) == 0)
		snapshot(renderer, surface, "search-loading")
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
		assert(state == 2 ? len(catalog.videos) == 1 && notice == "" : notice != "")
		if state < 2 {key(sdl.K_TAB)}
	}
}
