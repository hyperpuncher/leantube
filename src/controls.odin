package main

import clay "../vendor/clay"
import "./model"
import sb "./sponsorblock"
import sdl "vendor:sdl3"

Control_Button :: struct {
	id:   string,
	icon: Icon,
	key:  sdl.Keycode,
}
PAUSE_BUTTON :: Control_Button{"pause", .Pause, sdl.K_RETURN}
SLOWER_BUTTON :: Control_Button{"slower", .Slower, sdl.K_DOWN}
FASTER_BUTTON :: Control_Button{"faster", .Faster, sdl.K_UP}
control_buttons := [?]Control_Button{PAUSE_BUTTON, SLOWER_BUTTON, FASTER_BUTTON}

control_button :: proc(button: Control_Button) {
	color: clay.Color
	if clay.PointerOver(clay.ID(button.id)) {color = COLOR_HOVER}
	if clay.UI(clay.ID(button.id))(
	{
		layout = {
			sizing = {width = clay.SizingFixed(scaled(64)), height = clay.SizingFixed(scaled(64))},
			padding = clay.PaddingAll(spacing(8)),
			childAlignment = {x = .Center, y = .Center},
		},
		backgroundColor = color,
		cornerRadius = clay.CornerRadiusAll(scaled(32)),
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
	if !browsing {show_player_controls()}
	if browsing {
		if card_press.active &&
		   card_press.pointer &&
		   !clay.PointerOver(clay.ID("video", u32(card_press.index))) {
			card_press.active = false
		}
		if card_menu {card_menu_pointer(activate); return}
		if account_menu {
			if clay.PointerOver(clay.ID("account")) {
				if activate {account_menu = false; dirty = true}
				return
			}
			for _, i in auth_accounts {
				if clay.PointerOver(clay.ID("account-row", u32(i))) {
					account_menu_selected = i
					if activate {activate_account(i)}
					return
				}
			}
			if clay.PointerOver(clay.ID("add-account")) {
				account_menu_selected = len(auth_accounts)
				if activate {account_menu = false; start_login(true)}
				return
			}
			if clay.PointerOver(clay.ID("sign-out")) {
				account_menu_selected = len(auth_accounts) + int(len(auth_accounts) < MAX_ACCOUNTS)
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
		if clay.PointerOver(clay.ID("load-more")) {
			if activate {load_more()}
			return
		}
		for _, i in catalog.videos {
			if clay.PointerOver(clay.ID("video", u32(i))) {
				selected = i
				rail_focus = false
				if activate {
					if search_editing {finish_search_input(sdl.GetRenderWindow(renderer))}
					begin_card_press(true, sdl.GetTicks())
				}
				break
			}
		}
		return
	}
	if activate {
		if duration_ms > 0 && clay.PointerOver(clay.ID("timeline")) {
			box := clay.GetElementData(clay.ID("timeline")).boundingBox
			if box.width > 0 {
				fraction := clamp((point[0] - box.x) / box.width, 0, 1)
				seek_to(f64(fraction) * duration_ms)
				return
			}
		}
		for button in control_buttons {
			if clay.PointerOver(clay.ID(button.id)) {key(button.key); break}
		}
	}
}

TIMELINE_HEIGHT :: 28
TIMELINE_TRACK :: 4
TIMELINE_KNOB :: 14

timeline_span :: proc(
	id: clay.ElementId,
	start_ms, end_ms: f64,
	width: f32,
	color: clay.Color,
	layer: i16,
) {
	if clay.UI(id)(
	{
		layout = {
			sizing = {
				width = clay.SizingFixed(f32((end_ms - start_ms) / duration_ms) * width),
				height = clay.SizingFixed(scaled(TIMELINE_TRACK)),
			},
		},
		backgroundColor = color,
		cornerRadius = clay.CornerRadiusAll(scaled(TIMELINE_TRACK / 2)),
		floating = {
			attachTo = .Parent,
			offset = {f32(start_ms / duration_ms) * width, 0},
			zIndex = layer,
			pointerCaptureMode = .Passthrough,
		},
	},
	) {}
}

// The track is wide and the knob marks the position; a click seeks to it.
timeline_bar :: proc() {
	width := max(0, view_width - scaled(96))
	if clay.UI(clay.ID("timeline"))(
	{
		layout = {
			sizing = {
				width = clay.SizingGrow({}),
				height = clay.SizingFixed(scaled(TIMELINE_HEIGHT)),
			},
			childAlignment = {y = .Center},
		},
	},
	) {
		if clay.UI(clay.ID("timeline-track"))(
		{
			layout = {
				sizing = {
					width = clay.SizingGrow({}),
					height = clay.SizingFixed(scaled(TIMELINE_TRACK)),
				},
			},
			backgroundColor = COLOR_TRACK,
			cornerRadius = clay.CornerRadiusAll(scaled(TIMELINE_TRACK / 2)),
		},
		) {
			if duration_ms > 0 {
				for segment, i in sponsor_segments {
					if sb.can_skip(segment, duration_ms) {
						timeline_span(
							clay.ID("sponsor-marker", u32(i)),
							segment.start_ms,
							segment.end_ms,
							width,
							COLOR_SPONSOR,
							1,
						)
					}
				}
				position := clamp(model.display_position(timeline), 0, duration_ms)
				// Progress stays above markers, including when paused inside a segment.
				timeline_span(clay.ID("timeline-progress"), 0, position, width, COLOR_ACCENT, 2)
				knob := scaled(TIMELINE_KNOB)
				if clay.UI(clay.ID("timeline-knob"))(
				{
					layout = {
						sizing = {width = clay.SizingFixed(knob), height = clay.SizingFixed(knob)},
					},
					backgroundColor = COLOR_ACCENT,
					cornerRadius = clay.CornerRadiusAll(knob / 2),
					floating = {
						attachTo = .Parent,
						offset = {
							f32(position / duration_ms) * width - knob / 2,
							(scaled(TIMELINE_TRACK) - knob) / 2,
						},
						zIndex = 3,
						pointerCaptureMode = .Passthrough,
					},
				},
				) {}
			}
		}
	}
}

player_layout :: proc(elapsed, total, speed, quality: string) {
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
				childGap = spacing(16),
			},
			backgroundColor = COLOR_PANEL,
			cornerRadius = {topLeft = scaled(24), topRight = scaled(24)},
		},
		) {
			if clay.UI()(
			{
				layout = {
					sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(scaled(44))},
					childAlignment = {y = .Center},
				},
				clip = {horizontal = true, vertical = true},
			},
			) {label(loaded ? catalog.videos[selected].title : "Loading video…", .Body)}
			timeline_bar()
			if clay.UI()(
			{
				layout = {
					sizing = {width = clay.SizingGrow({})},
					childGap = spacing(20),
					childAlignment = {y = .Center},
				},
			},
			) {
				control_button(PAUSE_BUTTON)
				if clay.UI()({layout = {childGap = spacing(8), childAlignment = {y = .Center}}}) {
					label(elapsed, .Mono_Body)
					label("/", .Mono_Body, COLOR_MUTED)
					label(total, .Mono_Body, COLOR_MUTED)
				}
				if clay.UI()({layout = {sizing = {width = clay.SizingGrow({})}}}) {}
				// The buttons step the rate that sits between them.
				if clay.UI()({layout = {childGap = spacing(12), childAlignment = {y = .Center}}}) {
					control_button(SLOWER_BUTTON)
					if clay.UI()(
					{
						layout = {
							sizing = {width = clay.SizingFixed(scaled(112))},
							childAlignment = {x = .Center, y = .Center},
						},
					},
					) {label(speed, .Mono_Body, COLOR_MUTED)}
					control_button(FASTER_BUTTON)
				}
				if quality != "" {label(quality, .Mono_Body, COLOR_MUTED)}
			}
		}
	}
}
