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
	Mono_Small,
	Mono_Body,
}
BASE_TEXT_SIZES :: [Text_Style]u16 {
	.Body       = 32,
	.Small      = 26,
	.Caption    = 20,
	.Heading    = 36,
	.Mono_Small = 20,
	.Mono_Body  = 32,
}
text_sizes := BASE_TEXT_SIZES
fonts: [Text_Style]^ttf.Font
text_engine: ^ttf.TextEngine

open_text :: proc(renderer: ^sdl.Renderer) -> bool {
	if !ttf.Init() {return false}
	text_engine = ttf.CreateRendererTextEngine(renderer)
	if text_engine == nil {return false}
	for size, style in text_sizes {
		mono := style == .Mono_Small || style == .Mono_Body
		file := mono ? "GeistMono-Regular.ttf" : "Geist.ttf"
		path := fmt.caprintf("%s/fonts/%s", app_directory, file)
		fonts[style] = ttf.OpenFont(path, f32(size))
		delete(path)
		if fonts[style] == nil {return false}
	}
	return true
}

resize_text :: proc() -> bool {
	for base, style in BASE_TEXT_SIZES {
		size := u16(max(1, math.round(f32(base) * ui_scale)))
		if !ttf.SetFontSize(fonts[style], f32(size)) {return false}
		text_sizes[style] = size
	}
	return true
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
	measured: c.int
	if !ttf.GetStringSize(font, raw_data(text), c.size_t(len(text)), &measured, nil) {
		return "", false
	}
	if !continued && measured <= width {return text, false}
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
) {
	if text == "" || width <= 0 || max_lines < 1 {return text, false}
	line_height := c.int(ttf.GetFontHeight(font))
	if line_height <= 0 {return text, false}
	value := ttf.CreateText(text_engine, font, raw_data(text), c.size_t(len(text)))
	if value == nil {return text, false}
	defer ttf.DestroyText(value)
	if !ttf.SetTextWrapWidth(value, width) {return text, false}
	_, bounds_height: c.int
	if !ttf.GetTextSize(value, nil, &bounds_height) {return text, false}
	if bounds_height <= line_height * c.int(max_lines) {return text, false}
	line: ttf.SubString
	if !ttf.GetTextSubStringForLine(value, c.int(max_lines - 1), &line) {return text, false}
	line_end := line.offset + line.length
	if int(line_end) >= len(text) {return text, false}
	// Force the ellipsis: the visible line may fit, but text follows it.
	fitted, owned := fit_text(font, text[line.offset:line_end], width, true)
	if !owned {return text, false}
	defer delete(fitted)
	return strings.concatenate({text[:line.offset], fitted}), true
}

close_text :: proc() {
	if text_engine != nil {ttf.DestroyRendererTextEngine(text_engine); text_engine = nil}
	for font in fonts {ttf.CloseFont(font)}
	fonts = {}
	if ttf.WasInit() != 0 {ttf.Quit()}
}
