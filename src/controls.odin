package main

import clay "../vendor/clay"
import sb "./sponsorblock"
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
		if account_menu {
			if clay.PointerOver(clay.ID("account")) {
				if activate {account_menu = false; dirty = true}
				return
			}
			for _, i in auth_accounts {
				if clay.PointerOver(clay.ID("account-row", u32(i))) {
					if activate {activate_account(i)}
					return
				}
			}
			if clay.PointerOver(clay.ID("add-account")) {
				if activate {account_menu = false; start_login(true)}
				return
			}
			if clay.PointerOver(clay.ID("sign-out")) {
				if activate {sign_out()}
				return
			}
			if activate {account_menu = false; dirty = true}
			return
		}
		for item in Navigation {
			if clay.PointerOver(clay.ID("navigation-item", u32(item))) {
				if activate {
					rail_focus = true
					activate_navigation(item, sdl.GetRenderWindow(renderer))
				}
				return
			}
		}
		if clay.PointerOver(clay.ID("search")) {
			if activate {edit_search(sdl.GetRenderWindow(renderer))}
			return
		}
		for _, i in catalog.videos {
			if clay.PointerOver(clay.ID("video", u32(i))) {
				selected = i
				rail_focus = false
				if activate {
					if search_editing {finish_search_input(sdl.GetRenderWindow(renderer))}
					start_video()
				}
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

timeline_span :: proc(id: clay.ElementId, start_ms, end_ms: f64, color: clay.Color, layer: i16) {
	width := max(0, view_width - scaled(96))
	if clay.UI(id)(
	{
		layout = {
			sizing = {
				width = clay.SizingFixed(f32((end_ms - start_ms) / duration_ms) * width),
				height = clay.SizingFixed(scaled(6)),
			},
		},
		backgroundColor = color,
		floating = {
			attachTo = .Parent,
			offset = {f32(start_ms / duration_ms) * width, 0},
			zIndex = layer,
			pointerCaptureMode = .Passthrough,
		},
	},
	) {}
}

timeline_bar :: proc() {
	if clay.UI(clay.ID("timeline"))(
	{
		layout = {sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(scaled(6))}},
		backgroundColor = COLOR_TRACK,
	},
	) {
		if duration_ms > 0 {
			for segment, i in sponsor_segments {
				if sb.can_skip(segment, duration_ms) {
					timeline_span(
						clay.ID("sponsor-marker", u32(i)),
						segment.start_ms,
						segment.end_ms,
						COLOR_SPONSOR,
						1,
					)
				}
			}
			// Progress stays above markers, including when paused inside a segment.
			timeline_span(
				clay.ID("timeline-progress"),
				0,
				clamp(timeline.position_ms, 0, duration_ms),
				COLOR_ACCENT,
				2,
			)
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
			timeline_bar()
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
