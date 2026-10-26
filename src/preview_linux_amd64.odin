package main

import clay "../vendor/clay"
import "./model"
import "core:fmt"
import "core:os"
import sdl "vendor:sdl3"

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
	defer for texture in textures {if texture != nil {sdl.DestroyTexture(texture)}}
	defer model.catalog_destroy(&catalog)
	if !UI_TEST && len(os.args) > 1 {
		assert(load_catalog(renderer, "build/catalog"), "prepared catalog could not be loaded")
	} else {
		catalog.query = fmt.aprintf("local scrolling test · 24 videos")
		for i in 0 ..< model.MAX_VIDEOS {
			append(
				&catalog.videos,
				model.Video {
					title = fmt.aprintf(
						"video %02d · café and a longer title for layout checks",
						i + 1,
					),
					duration_ms = 100000,
					channel = fmt.aprintf("channel %02d", i + 1),
					duration_label = model.time_label(100000),
				},
			)
			pixels := [4]u8{u8(80 + i * 6), u8(80 + i * 6), u8(80 + i * 6), 255}
			textures[i] = sdl.CreateTexture(renderer, .RGBA32, .STATIC, 1, 1)
			assert(textures[i] != nil)
			assert(sdl.UpdateTexture(textures[i], nil, raw_data(pixels[:]), 4))
			assert(sdl.SetTextureBlendMode(textures[i], sdl.BLENDMODE_BLEND))
		}
	}
	clay.SetMaxElementCount(512)
	clay.SetMaxMeasureTextCacheWordCount(2048)
	memory := make([]u8, int(clay.MinMemorySize()))
	defer delete(memory)
	clay.Initialize(
		clay.CreateArenaWithCapacityAndMemory(uint(len(memory)), raw_data(memory)),
		{},
		{handler = clay_error},
	)
	clay.SetMeasureTextFunction(measure_text, nil)
	when UI_TEST {check_layout(renderer, surface)} else {run_dev(renderer)}
}

check_layout :: proc(renderer: ^sdl.Renderer, surface: ^sdl.Surface) {
	snapshot(renderer, surface, "start")
	initial_view := clay.GetElementData(clay.ID("library-scroll")).boundingBox
	assert(
		initial_view.y + initial_view.height == view_height,
		"the library must reach the bottom edge",
	)
	assert(icon_pixels == i32(scaled(48)))
	if os.args[1] == "4k" {
		assert(view_width == 3840 && view_height == 2160)
		assert(text_sizes[.Body] == BASE_TEXT_SIZES[.Body] * 2)
	}
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
	selected = model.MAX_VIDEOS - 1
	library_focus_pending = true
	snapshot(renderer, surface, "last")
	viewport := clay.GetElementData(clay.ID("library-scroll")).boundingBox
	last := clay.GetElementData(clay.ID("video", u32(selected))).boundingBox
	assert(last.y >= viewport.y && last.y + last.height <= viewport.y + viewport.height)
	scroll := clay.GetScrollContainerData(clay.ID("library-scroll"))
	before_player := scroll.scrollPosition^[1]
	key(sdl.K_RETURN)
	assert(!browsing && loaded && paused)
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
	assert(selected == model.MAX_VIDEOS - 1)
	assert(running)
	fmt.println(
		"scrolling, focus, player return, and antialiased fill/image edges passed; screenshots: build/ui-test",
	)
}
