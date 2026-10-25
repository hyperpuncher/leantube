package main

import clay "../vendor/clay"
import "base:runtime"
import "core:fmt"
import "core:strings"
import sdl "vendor:sdl3"

CONTROL_WIDTH :: 960
CONTROL_HEIGHT :: 540
Control_Button :: struct {
	id, label: string,
	key:       sdl.Scancode,
}
control_buttons := [?]Control_Button {
	{"seek-back", "< -10s", .LEFT},
	{"pause", "pause OK", .RETURN},
	{"seek-forward", "+10s >", .RIGHT},
	{"slower", "- rate", .DOWN},
	{"faster", "+ rate", .UP},
	{"close", "close", .ESCAPE},
}

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
control_button :: proc(button: Control_Button) {
	color: clay.Color = {44, 49, 60, 255}
	if button.key == .RETURN {color = {165, 35, 42, 255}}
	if clay.PointerOver(clay.ID(button.id)) {color = {95, 105, 125, 255}}
	if clay.UI(clay.ID(button.id))(
	{
		layout = {padding = {12, 12, 10, 10}, childAlignment = {y = .Center}},
		backgroundColor = color,
	},
	) {
		text := button.label
		if button.key == .RETURN {text = paused ? "play OK" : "pause OK"}
		label(text, 12)
	}
}
controls_pointer :: proc(renderer: ^sdl.Renderer, x, y: f32, down, activate: bool) {
	point: clay.Vector2
	if !sdl.RenderCoordinatesFromWindow(renderer, x, y, &point[0], &point[1]) {return}
	clay.SetPointerState(point, down)
	dirty = true
	if activate {
		for button in control_buttons {
			if clay.PointerOver(clay.ID(button.id)) {key(button.key); break}
		}
	}
}
render :: proc(renderer: ^sdl.Renderer) -> bool {
	if !sdl.SetRenderDrawColor(renderer, 0, 0, 0, 0) || !sdl.RenderClear(renderer) {return false}
	seconds := i64(position_ms / 1000)
	stamp: string
	if duration_ms > 0 {
		total := i64(duration_ms / 1000)
		stamp = fmt.aprintf(
			"%02d:%02d / %02d:%02d",
			seconds / 60,
			seconds % 60,
			total / 60,
			total % 60,
		)
	} else {
		stamp = fmt.aprintf("%02d:%02d / --:--", seconds / 60, seconds % 60)
	}
	defer delete(stamp)
	speed := fmt.aprintf("%.2fx", rate)
	defer delete(speed)
	state := !loaded ? "loading" : (paused ? "paused" : "playing")
	clay.BeginLayout()
	if clay.UI(clay.ID("root"))(
	{
		layout = {
			sizing = {
				width = clay.SizingFixed(CONTROL_WIDTH),
				height = clay.SizingFixed(CONTROL_HEIGHT),
			},
			layoutDirection = .TopToBottom,
		},
	},
	) {
		if clay.UI()({layout = {sizing = {height = clay.SizingGrow({})}}}) {}
		if clay.UI(clay.ID("controls"))(
		{
			layout = {
				sizing = {width = clay.SizingGrow({})},
				layoutDirection = .TopToBottom,
				padding = clay.PaddingAll(16),
				childGap = 12,
			},
			backgroundColor = {16, 20, 28, 230},
		},
		) {
			if clay.UI()(
			{
				layout = {
					sizing = {width = clay.SizingGrow({})},
					childGap = 16,
					childAlignment = {y = .Center},
				},
			},
			) {
				label("Big Buck Bunny")
				if clay.UI()({layout = {sizing = {width = clay.SizingGrow({})}}}) {}
				label(state, 12, {165, 175, 190, 255})
				label(stamp)
			}
			if clay.UI()(
			{
				layout = {sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(4)}},
				backgroundColor = {65, 70, 80, 255},
			},
			) {
				if duration_ms > 0 {
					if clay.UI()(
					{
						layout = {
							sizing = {
								width = clay.SizingFixed(
									f32(clamp(position_ms / duration_ms, 0, 1)) * 928,
								),
								height = clay.SizingFixed(4),
							},
						},
						backgroundColor = {230, 55, 65, 255},
					},
					) {}
				}
			}
			if clay.UI()(
			{
				layout = {
					sizing = {width = clay.SizingGrow({})},
					childGap = 8,
					childAlignment = {y = .Center},
				},
			},
			) {
				for button, i in control_buttons {
					if i == 3 {
						if clay.UI()({layout = {sizing = {width = clay.SizingGrow({})}}}) {}
						label(speed)
					}
					control_button(button)
				}
			}
		}
	}
	commands := clay.EndLayout(0)
	for i in 0 ..< commands.length {
		command := clay.RenderCommandArray_Get(&commands, i)
		box := command.boundingBox
		#partial switch command.commandType {
		case .Rectangle:
			color := command.renderData.rectangle.backgroundColor
			if !sdl.SetRenderDrawColor(
				renderer,
				u8(color[0]),
				u8(color[1]),
				u8(color[2]),
				u8(color[3]),
			) {return false}
			rect := sdl.FRect{box.x, box.y, box.width, box.height}
			if !sdl.RenderFillRect(renderer, &rect) {return false}
		case .Text:
			text := command.renderData.text
			color := text.textColor
			value := strings.clone_to_cstring(
				string(text.stringContents.chars[:text.stringContents.length]),
			)
			scale := f32(text.fontSize) / 8
			ok :=
				sdl.SetRenderDrawColor(
					renderer,
					u8(color[0]),
					u8(color[1]),
					u8(color[2]),
					u8(color[3]),
				) &&
				sdl.SetRenderScale(renderer, scale, scale) &&
				sdl.RenderDebugText(renderer, box.x / scale, box.y / scale, value)
			delete(value)
			_ = sdl.SetRenderScale(renderer, 1, 1)
			if !ok {return false}
		}
	}
	return sdl.RenderPresent(renderer)
}
