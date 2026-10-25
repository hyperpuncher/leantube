package main

import clay "../vendor/clay"
import sdl "vendor:sdl3"

Control_Button :: struct {
	id, label: string,
	key:       sdl.Keycode,
}
control_buttons := [?]Control_Button {
	{"seek-back", "< -10s", sdl.K_LEFT},
	{"pause", "pause OK", sdl.K_RETURN},
	{"seek-forward", "+10s >", sdl.K_RIGHT},
	{"slower", "- rate", sdl.K_DOWN},
	{"faster", "+ rate", sdl.K_UP},
	{"close", "back", sdl.K_ESCAPE},
}

control_button :: proc(button: Control_Button) {
	color: clay.Color = {44, 49, 60, 255}
	if button.key == sdl.K_RETURN {color = {165, 35, 42, 255}}
	if clay.PointerOver(clay.ID(button.id)) {color = {95, 105, 125, 255}}
	if clay.UI(clay.ID(button.id))(
	{
		layout = {padding = {12, 12, 10, 10}, childAlignment = {y = .Center}},
		backgroundColor = color,
	},
	) {
		text := button.label
		if button.key == sdl.K_RETURN {text = paused ? "play OK" : "pause OK"}
		label(text, 12)
	}
}
controls_pointer :: proc(renderer: ^sdl.Renderer, x, y: f32, down, activate: bool) {
	point: clay.Vector2
	if !sdl.RenderCoordinatesFromWindow(renderer, x, y, &point[0], &point[1]) {return}
	clay.SetPointerState(point, down)
	dirty = true
	if browsing {
		for _, i in catalog.videos {
			if clay.PointerOver(clay.ID("video", u32(i))) {
				selected = i
				if activate {start_video()}
				break
			}
		}
		return
	}
	if activate {
		for button in control_buttons {
			if clay.PointerOver(clay.ID(button.id)) {key(button.key); break}
		}
	}
}
player_layout :: proc(stamp, speed: string) {
	state := !loaded ? "loading" : (paused ? "paused" : "playing")
	if clay.UI(clay.ID("root"))(
	{
		layout = {
			sizing = {
				width = clay.SizingFixed(VIEW_WIDTH),
				height = clay.SizingFixed(VIEW_HEIGHT),
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
				label(catalog.videos[selected].player_label)
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
									f32(clamp(timeline.position_ms / duration_ms, 0, 1)) *
									f32(VIEW_WIDTH - 32),
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
}
