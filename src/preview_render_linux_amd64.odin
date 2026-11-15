package main

import clay "../vendor/clay"
import "core:c"
import "core:math"
import "core:strings"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

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
	save_snapshot(surface, "rounded-edges")
	// The gray track must not darken a completed bar at its rounded edge.
	assert(set_color(renderer, COLOR_ACCENT) && sdl.RenderClear(renderer))
	assert(
		rounded_progress(
			renderer,
			{16, 16, 64, 64},
			clay.CornerRadiusAll(16),
			100,
			{0, 0, surface.w, surface.h},
		),
	)
	assert(sdl.RenderPresent(renderer))
	for x in 16 ..< 32 {
		for y in 76 ..< 80 {
			red, green, blue: u8
			assert(sdl.ReadSurfacePixel(surface, i32(x), i32(y), &red, &green, &blue, nil))
			assert(
				math.abs(i32(red) - i32(COLOR_ACCENT[0])) <= 1 &&
				math.abs(i32(green) - i32(COLOR_ACCENT[1])) <= 1 &&
				math.abs(i32(blue) - i32(COLOR_ACCENT[2])) <= 1,
				"a completed bar must not leave a dark track at the rounded edge",
			)
		}
	}
	assert(set_color(renderer, COLOR_BACKGROUND) && sdl.RenderClear(renderer))
	assert(
		rounded_progress(
			renderer,
			{16.25, 16.25, 64.5, 64.5},
			clay.CornerRadiusAll(16),
			100,
			{0, 0, surface.w, surface.h},
		),
	)
	assert(sdl.RenderPresent(renderer))
	red: u8
	assert(sdl.ReadSurfacePixel(surface, 48, 80, &red, nil, nil, nil))
	assert(red > 0, "fractional cover bounds must not cut off the bottom progress edge")
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
	save_snapshot(surface, "cover-fill")
}

// Use real font measurements, including UTF-8 and an explicit final line.
check_text_fitting :: proc() {
	for sample in ([]string{"short", "café café café café café café", "a long channel name that must end with an ellipsis"}) {
		fit, owned := fit_text(fonts[.Small], sample, 160)
		defer if owned {delete(fit)}
		width: i32
		assert(ttf.GetStringSize(fonts[.Small], raw_data(fit), len(fit), &width, nil))
		assert(width <= 160)
		if owned {assert(strings.has_suffix(fit, "…"))} else {assert(fit == sample)}
	}
	// A dot leader is not an ASCII period. It must use the actual fallback glyph.
	dot_font: ^ttf.Font
	for fallback in fallback_fonts[.Caption] {
		if fallback != nil && ttf.FontHasGlyph(fallback, 0x2024) {dot_font = fallback; break}
	}
	if dot_font != nil && !ttf.FontHasGlyph(fonts[.Caption], 0x2024) {
		dot: string : "․"
		actual, expected: i32
		assert(ttf.GetStringSize(fonts[.Caption], raw_data(dot), len(dot), &actual, nil))
		assert(ttf.GetStringSize(dot_font, raw_data(dot), len(dot), &expected, nil))
		assert(actual > 0 && actual == expected, "text measurement must use the fallback glyph")
	}
	continued, owned := fit_text(fonts[.Small], "short", 160, true)
	defer if owned {delete(continued)}
	assert(strings.has_suffix(continued, "…"))
	too_narrow, _ := fit_text(fonts[.Small], "text", 1)
	assert(too_narrow == "")
	// Times and counts reuse Geist, so every digit must share one advance.
	advance: c.int
	for digit in '0' ..= '9' {
		width: c.int
		assert(ttf.GetGlyphMetrics(fonts[.Body], u32(digit), nil, nil, nil, nil, &width))
		if digit == '0' {advance = width}
		assert(width == advance, "digits must not change width")
	}
	// A wrapped title is fitted to two lines and keeps the trailing ellipsis.
	wrapped, wrapped_owned, wrapped_lines := fit_wrapped(
		fonts[.Small],
		"a very long video title that keeps going well past two lines of text for the card",
		400,
		2,
	)
	defer if wrapped_owned {delete(wrapped)}
	assert(wrapped_lines == 2 && strings.has_suffix(wrapped, "…"))
	line_height := c.int(ttf.GetFontHeight(fonts[.Small]))
	probe := ttf.CreateText(text_engine, fonts[.Small], raw_data(wrapped), c.size_t(len(wrapped)))
	assert(probe != nil)
	assert(ttf.SetTextWrapWidth(probe, 400))
	wrapped_width, wrapped_height: c.int
	assert(ttf.GetTextSize(probe, &wrapped_width, &wrapped_height))
	ttf.DestroyText(probe)
	assert(wrapped_width <= 400)
	assert(wrapped_height <= 2 * line_height, "a fitted title must wrap to two lines at most")
	fits, fits_owned, fits_lines := fit_wrapped(fonts[.Small], "short title", 400, 2)
	assert(!fits_owned && fits_lines == 1 && fits == "short title")
}
