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
SLOWER_BUTTON :: Control_Button{"slower", .Slower, sdl.K_DOWN}
FASTER_BUTTON :: Control_Button{"faster", .Faster, sdl.K_UP}
control_buttons := [?]Control_Button{SLOWER_BUTTON, FASTER_BUTTON}

// The rate stepper is one light pill. It is muted like the other labels,
// and a button turns white under the pointer.
STEPPER_FILL :: clay.Color{255, 255, 255, 24}
STEPPER_HOVER :: clay.Color{255, 255, 255, 40}
STEPPER_BUTTON :: 44
STEPPER_INSET :: 6
stepper_muted := COLOR_MUTED

control_button :: proc(button: Control_Button) {
	hovered := clay.PointerOver(clay.ID(button.id))
	if clay.UI(clay.ID(button.id))(
	{
		layout = {
			sizing = {
				width = clay.SizingFixed(scaled(STEPPER_BUTTON)),
				height = clay.SizingFixed(scaled(STEPPER_BUTTON)),
			},
			childAlignment = {x = .Center, y = .Center},
		},
		backgroundColor = hovered ? STEPPER_HOVER : {},
		cornerRadius = clay.CornerRadiusAll(scaled(STEPPER_BUTTON / 2)),
	},
	) {icon(button.icon, 28, hovered ? nil : &stepper_muted)}
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

// Reserve the slot before the stream reports the channel, so the title
// keeps its height and line breaks when the avatar appears.
player_channel_button :: proc() {
	if player_channel_id == "" {
		size := scaled(PLAYER_AVATAR_SIZE + 2 * 8)
		if clay.UI()(
		{layout = {sizing = {width = clay.SizingFixed(size), height = clay.SizingFixed(size)}}},
		) {}
		return
	}
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

// The track width depends on the labels beside it, so spans are fractions of
// the track. A floating row fills the track, and a spacer moves each span.
timeline_span :: proc(
	id: clay.ElementId,
	start_ms, end_ms: f64,
	height: f32,
	color: clay.Color,
	layer: i16,
	rounded: bool = true,
) {
	fill := color
	fill[3] = TIMELINE_ALPHA
	if clay.UI()(
	{
		layout = {sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})}},
		floating = {attachTo = .Parent, zIndex = layer, pointerCaptureMode = .Passthrough},
	},
	) {
		if clay.UI()(
		{layout = {sizing = {width = clay.SizingPercent(f32(start_ms / duration_ms))}}},
		) {}
		if clay.UI(id)(
		{
			layout = {
				sizing = {
					width = clay.SizingPercent(f32((end_ms - start_ms) / duration_ms)),
					height = clay.SizingFixed(height),
				},
			},
			backgroundColor = fill,
			cornerRadius = clay.CornerRadiusAll(rounded ? height / 2 : 0),
		},
		) {}
	}
}

// The track is wide and the knob marks the position; a click seeks to it.
timeline_bar :: proc() {
	track_color := COLOR_TRACK
	track_color[3] = TIMELINE_ALPHA
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
				   start {timeline_span(clay.ID("timeline-buffered"), start, end, height, COLOR_BUFFERED, 1)}
				for segment, i in sponsor_segments {
					if sb.can_skip(segment, duration_ms) {
						timeline_span(
							clay.ID("sponsor-marker", u32(i)),
							segment.start_ms,
							segment.end_ms,
							height,
							COLOR_SPONSOR,
							2,
							rounded = false,
						)
					}
				}
				position := clamp(shown_position(), 0, duration_ms)
				// Progress stays above markers, including when paused inside a segment.
				timeline_span(clay.ID("timeline-progress"), 0, position, height, COLOR_ACCENT, 3)
				// The spacer ends at the position. Shift the row left by half a
				// knob, so the knob centre marks the position.
				if clay.UI()(
				{
					layout = {
						sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
						childAlignment = {y = .Center},
					},
					floating = {
						attachTo = .Parent,
						offset = {-knob / 2, 0},
						zIndex = 4,
						pointerCaptureMode = .Passthrough,
					},
				},
				) {
					if clay.UI()(
					{
						layout = {
							sizing = {width = clay.SizingPercent(f32(position / duration_ms))},
						},
					},
					) {}
					if clay.UI(clay.ID("timeline-knob"))(
					{
						layout = {
							sizing = {
								width = clay.SizingFixed(knob),
								height = clay.SizingFixed(knob),
							},
						},
						backgroundColor = COLOR_ACCENT,
						cornerRadius = clay.CornerRadiusAll(knob / 2),
					},
					) {}
				}
			}
		}
	}
}

// Labels centre their line box, which puts digits below the row centre.
// Lift the ink to the centre of the track and the icons.
digits_label :: proc(text: string, color: clay.Color = COLOR_TEXT) {
	if clay.UI()(
	{layout = {padding = {bottom = u16(max(0, 2 * digit_ink_shift[.Body]))}}},
	) {label(text, .Body, color)}
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
		// One row: time, timeline, duration, optional speed, and quality.
		if clay.UI(clay.ID("controls"))(
		{
			layout = {
				sizing = {width = clay.SizingGrow({})},
				padding = padding(48, 48, 24, 32),
				childGap = spacing(24),
				childAlignment = {y = .Center},
			},
		},
		) {
			digits_label(elapsed)
			timeline_bar()
			digits_label(total, COLOR_MUTED)
			// The buttons step the rate that sits between them.
			if speed != "" {
				if clay.UI(clay.ID("rate"))(
				{
					layout = {
						padding = clay.PaddingAll(spacing(STEPPER_INSET)),
						childGap = spacing(4),
						childAlignment = {y = .Center},
					},
					backgroundColor = STEPPER_FILL,
					cornerRadius = clay.CornerRadiusAll(
						scaled(STEPPER_BUTTON / 2 + STEPPER_INSET),
					),
				},
				) {
					control_button(SLOWER_BUTTON)
					if clay.UI()(
					{
						layout = {
							sizing = {width = clay.SizingFixed(scaled(104))},
							childAlignment = {x = .Center, y = .Center},
						},
					},
					) {digits_label(speed, COLOR_MUTED)}
					control_button(FASTER_BUTTON)
				}
			}
			// Reserve the quality slot before the media service reports it.
			if clay.UI()(
			{
				layout = {
					sizing = {width = clay.SizingFixed(scaled(64))},
					childAlignment = {x = .Right, y = .Center},
				},
			},
			) {if quality != "" {digits_label(quality, COLOR_MUTED)}}
		}
	}
}

// Playing controls fade out after a few quiet seconds and any input revives them.
// A zero deadline means hidden.
PLAYER_CONTROLS_MS :: 3000
controls_until: u64

show_player_controls :: proc() {controls_until = sdl.GetTicks() + PLAYER_CONTROLS_MS}

player_controls_visible :: proc() -> bool {
	return(
		paused ||
		!loaded ||
		sdl.GetTicks() < controls_until ||
		clay.PointerOver(clay.ID("controls")) ||
		clay.PointerOver(clay.ID("player-header")) \
	)
}

expire_player_controls :: proc() {
	if browsing || controls_until == 0 || player_controls_visible() {return}
	controls_until = 0
	dirty = true
}
