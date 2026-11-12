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
	if clay.PointerOver(clay.ID(button.id)) {
		color = COLOR_HOVER
		color[3] = COLOR_BADGE[3]
	}
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
	if login_screen {
		if activate {
			if clay.PointerOver(
				clay.ID("login-search"),
			) {leave_login(sdl.GetRenderWindow(renderer))}
			if clay.PointerOver(clay.ID("login-retry")) {retry_login()}
		}
		return
	}
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
		if search_editing {
			if activate {
				if clay.PointerOver(clay.ID("search")) {
					search_pointer(point[0], sdl.GetModState() & sdl.KMOD_SHIFT != {})
				} else {finish_search_input(sdl.GetRenderWindow(renderer))}
			}
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
		if channel_pointer(activate) {return}
		first, last := visible_rows()
		for i in first * grid_columns ..< min(last * grid_columns, len(catalog.videos)) {
			video := catalog.videos[i]
			if clay.PointerOver(clay.ID("watch-later", u32(i))) {
				card_press.active = false
				selected = i
				rail_focus, channel_focus = false, false
				if activate {
					if search_editing {finish_search_input(sdl.GetRenderWindow(renderer))}
					toggle_watch_later(video.id)
				}
				return
			}
			if clay.PointerOver(clay.ID("card-avatar", u32(i))) {
				card_press.active = false
				selected = i
				rail_focus, channel_focus = false, false
				if activate {start_browse(model.video_channel_id(video))}
				return
			}
			if clay.PointerOver(clay.ID("video", u32(i))) {
				selected = i
				rail_focus = false
				channel_focus = false
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
		if clay.PointerOver(clay.ID("player-channel")) {open_player_channel(); return}
		if duration_ms > 0 && timeline_hovered() {
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

player_channel_button :: proc() {
	if player_channel_id == "" {return}
	avatar_button(
		clay.ID("player-channel"),
		player_channel_avatar,
		PLAYER_AVATAR_SIZE,
		8,
		COLOR_BADGE[3],
	)
}

TIMELINE_ALPHA :: 204 // 80% opacity; keep the knob solid.
TIMELINE_HEIGHT :: 44
TIMELINE_TRACK :: 6
TIMELINE_TRACK_HOVER :: 12
TIMELINE_KNOB :: 18
TIMELINE_KNOB_HOVER :: 28

timeline_hovered :: proc() -> bool {return(
		clay.PointerOver(clay.ID("timeline")) ||
		clay.PointerOver(clay.ID("timeline-knob")) \
	)}

timeline_span :: proc(
	id: clay.ElementId,
	start_ms, end_ms: f64,
	width, height: f32,
	color: clay.Color,
	layer: i16,
	rounded: bool = true,
) {
	fill := color
	fill[3] = TIMELINE_ALPHA
	if clay.UI(id)(
	{
		layout = {
			sizing = {
				width = clay.SizingFixed(f32((end_ms - start_ms) / duration_ms) * width),
				height = clay.SizingFixed(height),
			},
		},
		backgroundColor = fill,
		cornerRadius = clay.CornerRadiusAll(rounded ? height / 2 : 0),
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
	track_color := COLOR_TRACK
	track_color[3] = TIMELINE_ALPHA
	width := max(0, view_width - scaled(96))
	hovered := timeline_hovered()
	height := scaled(hovered ? TIMELINE_TRACK_HOVER : TIMELINE_TRACK)
	knob := scaled(hovered ? TIMELINE_KNOB_HOVER : TIMELINE_KNOB)
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
			layout = {sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(height)}},
			backgroundColor = track_color,
			cornerRadius = clay.CornerRadiusAll(height / 2),
		},
		) {
			if duration_ms > 0 {
				start := clamp(timeline.buffer_start_ms, 0, duration_ms)
				end := clamp(timeline.buffer_end_ms, start, duration_ms)
				if end >
				   start {timeline_span(clay.ID("timeline-buffered"), start, end, width, height, COLOR_BUFFERED, 1)}
				for segment, i in sponsor_segments {
					if sb.can_skip(segment, duration_ms) {
						timeline_span(
							clay.ID("sponsor-marker", u32(i)),
							segment.start_ms,
							segment.end_ms,
							width,
							height,
							COLOR_SPONSOR,
							2,
							rounded = false,
						)
					}
				}
				position := clamp(model.display_position(timeline), 0, duration_ms)
				// Progress stays above markers, including when paused inside a segment.
				timeline_span(
					clay.ID("timeline-progress"),
					0,
					position,
					width,
					height,
					COLOR_ACCENT,
					3,
				)
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
							(height - knob) / 2,
						},
						zIndex = 4,
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
		if !loaded {centered_spinner()}
		if clay.UI(clay.ID("player-header"))(
		{
			layout = {
				sizing = {width = clay.SizingGrow({}), height = clay.SizingFit({})},
				padding = padding(48, 48, 32, 32),
				childGap = spacing(24),
				childAlignment = {y = .Center},
			},
		},
		) {
			if clay.UI()(
			{layout = {sizing = {width = clay.SizingGrow({})}}, clip = {horizontal = true}},
			) {
				if selected >= 0 && selected < len(catalog.videos) {
					label(catalog.videos[selected].title, .Player_Title, wrap = .Words)
				}
			}
			player_channel_button()
		}
		if clay.UI()({layout = {sizing = {height = clay.SizingGrow({})}}}) {}
		if clay.UI(clay.ID("controls"))(
		{
			layout = {
				sizing = {width = clay.SizingGrow({})},
				layoutDirection = .TopToBottom,
				padding = padding(48, 48, 24, 24),
				childGap = spacing(16),
			},
		},
		) {
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
					label(elapsed, .Body)
					label("/", .Body, COLOR_MUTED)
					label(total, .Body, COLOR_MUTED)
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
					) {label(speed, .Body, COLOR_MUTED)}
					control_button(FASTER_BUTTON)
				}
				// Reserve the quality slot before the media service reports it.
				if clay.UI()(
				{
					layout = {
						sizing = {width = clay.SizingFixed(scaled(112))},
						childAlignment = {x = .Right, y = .Center},
					},
				},
				) {if quality != "" {label(quality, .Body, COLOR_MUTED)}}
			}
		}
	}
}
