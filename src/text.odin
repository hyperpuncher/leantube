package main

import "core:c"
import "core:fmt"
import "core:math"
import "core:strings"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

Text_Style :: enum u16 {
	Body,
	Small,
	Caption,
	Heading,
	Title,
	Player_Title,
}
BASE_TEXT_SIZES :: [Text_Style]u16 {
	.Body         = 32,
	.Small        = 26,
	.Caption      = 20,
	.Heading      = 36,
	.Title        = 56,
	.Player_Title = 48,
}
text_sizes := BASE_TEXT_SIZES
fonts: [Text_Style]^ttf.Font
// SDL centres the line box, not the glyphs, so digits sit below the middle of a
// chip. Keep the offset that puts their ink in the middle instead.
digit_ink_shift: [Text_Style]i32
// Preserve fallback order. Relative paths refer to bundled fonts.
fallback_fonts: [Text_Style][len(FALLBACK_FONT_PATHS)]^ttf.Font
text_engine: ^ttf.TextEngine
// Reuse visible text slots in draw order. SDL owns each slot's string.
rendered_text: [dynamic]^ttf.Text

frame_text :: proc(index: int, font: ^ttf.Font, display: string) -> ^ttf.Text {
	if index == len(rendered_text) {
		value := ttf.CreateText(text_engine, font, raw_data(display), c.size_t(len(display)))
		if value == nil {return nil}
		append(&rendered_text, value)
	}
	value := rendered_text[index]
	if ttf.GetTextFont(value) != font && !ttf.SetTextFont(value, font) {return nil}
	if string(cstring(value.text)) != display &&
	   !ttf.SetTextString(value, raw_data(display), c.size_t(len(display))) {return nil}
	return value
}

open_text :: proc(renderer: ^sdl.Renderer) -> bool {
	if !ttf.Init() {return false}
	properties := sdl.CreateProperties()
	if properties == 0 {return false}
	defer sdl.DestroyProperties(properties)
	// GLES uploads the whole atlas for each new glyph. Keep those uploads small.
	if !sdl.SetPointerProperty(properties, ttf.PROP_RENDERER_TEXT_ENGINE_RENDERER, renderer) ||
	   !sdl.SetNumberProperty(properties, ttf.PROP_RENDERER_TEXT_ENGINE_ATLAS_TEXTURE_SIZE, 128) {
		return false
	}
	text_engine = ttf.CreateRendererTextEngineWithProperties(properties)
	if text_engine == nil {return false}
	// Fallbacks are optional. Missing fonts must not prevent startup.
	sources: [len(FALLBACK_FONT_PATHS)]^ttf.Font
	for path, i in FALLBACK_FONT_PATHS {
		if string(path) == "" {continue}
		resolved := path
		owned: cstring
		defer delete(owned)
		if !strings.has_prefix(string(path), "/") {
			owned = fmt.caprintf("%s/%s", app_directory, path)
			resolved = owned
		}
		sources[i] = ttf.OpenFont(resolved, f32(text_sizes[.Body]))
	}
	defer for source in sources {if source != nil {ttf.CloseFont(source)}}
	path := fmt.caprintf("%s/fonts/Geist.ttf", app_directory)
	defer delete(path)
	for size, style in text_sizes {
		// Geist's sixth named instance is SemiBold (600).
		face: sdl.Sint64 = style == .Player_Title ? 6 << 16 : 0
		configured :=
			sdl.SetStringProperty(properties, ttf.PROP_FONT_CREATE_FILENAME_STRING, path) &&
			sdl.SetFloatProperty(properties, ttf.PROP_FONT_CREATE_SIZE_FLOAT, f32(size)) &&
			sdl.SetNumberProperty(properties, ttf.PROP_FONT_CREATE_FACE_NUMBER, face)
		if !configured {return false}
		fonts[style] = ttf.OpenFontWithProperties(properties)
		if fonts[style] == nil {return false}
		for source, i in sources {
			if source == nil {continue}
			fallback := ttf.CopyFont(source)
			fallback_fonts[style][i] = fallback
			if fallback == nil ||
			   !ttf.SetFontSize(fallback, f32(size)) ||
			   !ttf.AddFallbackFont(fonts[style], fallback) {return false}
		}
	}
	return true
}

resize_text :: proc() -> bool {
	for base, style in BASE_TEXT_SIZES {
		size := u16(max(1, math.round(f32(base) * ui_scale)))
		for fallback in fallback_fonts[style] {
			if fallback != nil && !ttf.SetFontSize(fallback, f32(size)) {return false}
		}
		if !ttf.SetFontSize(fonts[style], f32(size)) {return false}
		text_sizes[style] = size
		digit_ink_shift[style] = digit_ink_shift_for(fonts[style])
	}
	return true
}

// Digits share one vertical extent and have no descenders, so their ink centre
// is this far below the line box centre.
digit_ink_shift_for :: proc(font: ^ttf.Font) -> i32 {
	if font == nil {return 0}
	top, bottom: c.int
	for digit in '0' ..= '9' {
		min_y, max_y: c.int
		if !ttf.GetGlyphMetrics(font, u32(digit), nil, nil, &min_y, &max_y, nil) {return 0}
		if digit == '0' {top, bottom = max_y, min_y} else {
			top = max(top, max_y)
			bottom = min(bottom, min_y)
		}
	}
	height := ttf.GetFontHeight(font)
	ascent := ttf.GetFontAscent(font)
	return (2 * i32(ascent) - i32(height) - i32(top + bottom)) / 2
}

// Return a borrowed string when it fits; otherwise the caller owns the result.
fit_text :: proc(
	font: ^ttf.Font,
	text: string,
	width: c.int,
	continued: bool = false,
) -> (
	string,
	bool,
) {
	if text == "" || width <= 0 {return "", false}
	if !continued {
		measured: c.int
		if !ttf.GetStringSize(font, raw_data(text), c.size_t(len(text)), &measured, nil) {
			return "", false
		}
		if measured <= width {return text, false}
	}
	ELLIPSIS: string : "…"
	ellipsis_width: c.int
	if !ttf.GetStringSize(font, raw_data(ELLIPSIS), len(ELLIPSIS), &ellipsis_width, nil) {
		return "", false
	}
	if ellipsis_width > width {return "", false}
	length: c.size_t
	if width > ellipsis_width {
		if !ttf.MeasureString(
			font,
			raw_data(text),
			c.size_t(len(text)),
			width - ellipsis_width,
			nil,
			&length,
		) {
			return "", false
		}
	}
	prefix := strings.trim_right_space(text[:int(length)])
	return strings.concatenate({prefix, ELLIPSIS}), true
}

// Wrap text into at most max_lines at width, ellipsizing the last visible line.
// Return a borrowed string when everything fits; otherwise the caller owns it.
// SDL_ttf wraps the text, so the line count matches the drawn result exactly.
fit_wrapped :: proc(
	font: ^ttf.Font,
	text: string,
	width: c.int,
	max_lines: int,
) -> (
	string,
	bool,
	int,
) {
	if text == "" || width <= 0 || max_lines < 1 {return text, false, 1}
	line_height := c.int(ttf.GetFontHeight(font))
	if line_height <= 0 {return text, false, 1}
	// Measurement needs shaping only, not renderer glyph uploads.
	value := ttf.CreateText(nil, font, raw_data(text), c.size_t(len(text)))
	if value == nil {return text, false, 1}
	defer ttf.DestroyText(value)
	if !ttf.SetTextWrapWidth(value, width) {return text, false, 1}
	_, bounds_height: c.int
	if !ttf.GetTextSize(value, nil, &bounds_height) {return text, false, 1}
	lines := clamp((bounds_height + line_height - 1) / line_height, 1, c.int(max_lines))
	if bounds_height <= line_height * c.int(max_lines) {return text, false, int(lines)}
	line: ttf.SubString
	if !ttf.GetTextSubStringForLine(value, c.int(max_lines - 1), &line) {return text, false, 1}
	line_end := line.offset + line.length
	if int(line_end) >= len(text) {return text, false, int(lines)}
	// Force the ellipsis: the visible line may fit, but text follows it.
	fitted, owned := fit_text(font, text[line.offset:line_end], width, true)
	if !owned {return text, false, int(lines)}
	defer delete(fitted)
	return strings.concatenate({text[:line.offset], fitted}), true, int(lines)
}

close_text :: proc() {
	for value in rendered_text {ttf.DestroyText(value)}
	delete(rendered_text); rendered_text = nil
	if text_engine != nil {ttf.DestroyRendererTextEngine(text_engine); text_engine = nil}
	for font in fonts {ttf.CloseFont(font)}
	for fallbacks in fallback_fonts {for font in fallbacks {if font != nil {ttf.CloseFont(font)}}}
	fonts, fallback_fonts = {}, {}
	if ttf.WasInit() != 0 {ttf.Quit()}
}
