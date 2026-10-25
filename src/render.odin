package main

import clay "../vendor/clay"
import "./model"
import "base:runtime"
import "core:fmt"
import "core:strings"
import sdl "vendor:sdl3"

VIEW_WIDTH :: 960
VIEW_HEIGHT :: 540

clay_error :: proc "c" (error: clay.ErrorData) {
	context = runtime.default_context()
	fmt.eprintln("layout error:", string(error.errorText.chars[:error.errorText.length]))
	running = false
}
measure_text :: proc "c" (
	text: clay.StringSlice,
	config: ^clay.TextElementConfig,
	data: rawptr,
) -> clay.Dimensions {
	return {f32(text.length) * f32(config.fontSize), f32(config.fontSize)}
}
label :: proc(text: string, size: u16 = 16, color: clay.Color = {240, 242, 246, 255}) {
	clay.Text(text, {fontSize = size, textColor = color, wrapMode = .None})
}

set_color :: proc(renderer: ^sdl.Renderer, color: clay.Color) -> bool {
	return sdl.SetRenderDrawColor(renderer, u8(color[0]), u8(color[1]), u8(color[2]), u8(color[3]))
}

render :: proc(renderer: ^sdl.Renderer) -> bool {
	color: clay.Color
	if browsing {color = {12, 16, 24, 255}}
	if !set_color(renderer, color) || !sdl.RenderClear(renderer) {return false}
	// Clay borrows these strings until the render commands have been drawn.
	stamp, speed: string
	defer {delete(stamp); delete(speed)}
	clay.BeginLayout()
	if browsing {
		grid_layout()
	} else {
		elapsed := model.time_label(timeline.position_ms)
		total := model.time_label(duration_ms, "--:--")
		stamp = fmt.aprintf("%s / %s", elapsed, total)
		delete(elapsed)
		delete(total)
		speed = fmt.aprintf("%.2fx", rate)
		player_layout(stamp, speed)
	}
	return render_commands(renderer, clay.EndLayout(0))
}

render_commands :: proc(
	renderer: ^sdl.Renderer,
	input: clay.ClayArray(clay.RenderCommand),
) -> bool {
	commands := input
	for i in 0 ..< commands.length {
		command := clay.RenderCommandArray_Get(&commands, i)
		box := command.boundingBox
		rect := sdl.FRect{box.x, box.y, box.width, box.height}
		#partial switch command.commandType {
		case .Rectangle:
			color := command.renderData.rectangle.backgroundColor
			if !set_color(renderer, color) {return false}
			if !sdl.RenderFillRect(renderer, &rect) {return false}
		case .Image:
			texture := cast(^sdl.Texture)command.renderData.image.imageData
			if !sdl.RenderTexture(renderer, texture, nil, &rect) {return false}
		case .Text:
			text := command.renderData.text
			color := text.textColor
			value := strings.clone_to_cstring(
				string(text.stringContents.chars[:text.stringContents.length]),
			)
			scale := f32(text.fontSize) / 8
			ok :=
				set_color(renderer, color) &&
				sdl.SetRenderScale(renderer, scale, scale) &&
				sdl.RenderDebugText(renderer, box.x / scale, box.y / scale, value)
			delete(value)
			_ = sdl.SetRenderScale(renderer, 1, 1)
			if !ok {return false}
		}
	}
	return sdl.RenderPresent(renderer)
}
