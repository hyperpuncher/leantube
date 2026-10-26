package main

import "core:fmt"
import "core:math"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

Text_Style :: enum u16 {
	Body,
	Small,
	Caption,
	Heading,
	Mono_Small,
}
BASE_TEXT_SIZES :: [Text_Style]u16 {
	.Body       = 32,
	.Small      = 26,
	.Caption    = 20,
	.Heading    = 36,
	.Mono_Small = 20,
}
text_sizes := BASE_TEXT_SIZES
fonts: [Text_Style]^ttf.Font
text_engine: ^ttf.TextEngine

open_text :: proc(renderer: ^sdl.Renderer) -> bool {
	if !ttf.Init() {return false}
	text_engine = ttf.CreateRendererTextEngine(renderer)
	if text_engine == nil {return false}
	for size, style in text_sizes {
		file := style == .Mono_Small ? "GeistMono-Regular.ttf" : "Geist.ttf"
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

close_text :: proc() {
	if text_engine != nil {ttf.DestroyRendererTextEngine(text_engine); text_engine = nil}
	for font in fonts {ttf.CloseFont(font)}
	fonts = {}
	if ttf.WasInit() != 0 {ttf.Quit()}
}
