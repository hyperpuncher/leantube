package main

import clay "../vendor/clay"
import sdl "vendor:sdl3"

Control_Button :: struct {
	id:   string,
	icon: Icon,
	key:  sdl.Keycode,
}
control_buttons := [?]Control_Button {
	{"seek-back", .Seek_Back, sdl.K_LEFT},
	{"pause", .Pause, sdl.K_RETURN},
	{"seek-forward", .Seek_Forward, sdl.K_RIGHT},
	{"slower", .Slower, sdl.K_DOWN},
	{"faster", .Faster, sdl.K_UP},
}

control_button :: proc(button: Control_Button) {
	color: clay.Color
	if button.key == sdl.K_RETURN {color = COLOR_SURFACE}
	if clay.PointerOver(clay.ID(button.id)) {color = COLOR_HOVER}
	if clay.UI(clay.ID(button.id))(
	{
		layout = {
			sizing = {width = clay.SizingFixed(scaled(72)), height = clay.SizingFixed(scaled(72))},
			padding = clay.PaddingAll(spacing(12)),
			childGap = spacing(8),
			childAlignment = {x = .Center, y = .Center},
		},
		backgroundColor = color,
		cornerRadius = clay.CornerRadiusAll(scaled(36)),
	},
	) {
		glyph := button.icon
		if button.key == sdl.K_RETURN && paused {glyph = .Play}
		icon(glyph)
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
	if clay.UI(clay.ID("root"))(
	{
		layout = {
			sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
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
				padding = padding(48, 48, 24, 24),
				childGap = spacing(20),
			},
			backgroundColor = COLOR_PANEL,
		},
		) {
			if clay.UI()(
			{
				layout = {
					sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(scaled(44))},
				},
				clip = {horizontal = true, vertical = true},
			},
			) {label(loaded ? catalog.videos[selected].title : "Loading video…")}
			if clay.UI()(
			{
				layout = {
					sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(scaled(6))},
				},
				backgroundColor = COLOR_TRACK,
			},
			) {
				if duration_ms > 0 {
					if clay.UI()(
					{
						layout = {
							sizing = {
								width = clay.SizingFixed(
									f32(clamp(timeline.position_ms / duration_ms, 0, 1)) *
									(view_width - scaled(96)),
								),
								height = clay.SizingFixed(scaled(6)),
							},
						},
						backgroundColor = COLOR_ACCENT,
					},
					) {}
				}
			}
			if clay.UI()(
			{
				layout = {
					sizing = {width = clay.SizingGrow({})},
					childGap = spacing(16),
					childAlignment = {y = .Center},
				},
			},
			) {
				for button, i in control_buttons {
					if i == 3 {
						label(stamp, .Mono_Small)
						if clay.UI()({layout = {sizing = {width = clay.SizingGrow({})}}}) {}
						label(speed, .Mono_Small)
					}
					control_button(button)
				}
			}
		}
	}
}
