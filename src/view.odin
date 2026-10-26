package main

import clay "../vendor/clay"
import "core:c"
import "core:math"
import sdl "vendor:sdl3"

view_width, view_height: f32
ui_scale: f32 = 1
grid_columns: int = 3

// Design spacing is in display units. Clay and SDL draw in native pixels.
scaled :: proc(value: f32) -> f32 {return value * ui_scale}
spacing :: proc(value: u16) -> u16 {return u16(math.round(f32(value) * ui_scale))}
padding :: proc(left, right, top, bottom: u16) -> clay.Padding {
	return {spacing(left), spacing(right), spacing(top), spacing(bottom)}
}

refresh_view :: proc(renderer: ^sdl.Renderer) -> bool {
	width, height: c.int
	if !sdl.GetRenderOutputSize(renderer, &width, &height) {return false}
	scale := ui_scale // Offscreen tests provide the display scale explicitly.
	if window := sdl.GetRenderWindow(renderer); window != nil {
		scale = sdl.GetWindowDisplayScale(window)
		if scale <= 0 {return false}
	}
	density_changed := view_width == 0 || ui_scale != scale
	changed := view_width != f32(width) || view_height != f32(height) || density_changed
	view_width, view_height, ui_scale = f32(width), f32(height), scale
	clay.SetLayoutDimensions({view_width, view_height})
	if density_changed {
		if !resize_text() {return false}
		clay.ResetMeasureTextCache()
	}
	if changed {
		if !open_icons(renderer) {return false}
		// Cards fill each row; only their readable minimum width is a design value.
		grid_columns = max(1, int((view_width - scaled(128) + scaled(32)) / scaled(480 + 32)))
		library_focus_pending = true
	}
	return true
}
