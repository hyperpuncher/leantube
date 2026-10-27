package main

import clay "../vendor/clay"
import "./model"
import sdl "vendor:sdl3"

CARD_HOLD_MS :: 650
card_press: struct {
	active, pointer: bool,
	started:         u64,
	page:            u32,
	index:           int,
}
card_menu: bool
card_menu_selected: int
card_menu_actions: [dynamic]model.Card_Action
card_menu_waiting: bool
card_menu_revision: int
card_menu_error: string

can_press_card :: proc() -> bool {
	return(
		browsing &&
		!rail_focus &&
		!search_editing &&
		!account_menu &&
		!login_screen &&
		!card_menu &&
		selected >= 0 &&
		selected < len(catalog.videos) \
	)
}

begin_card_press :: proc(pointer: bool, now: u64) {
	if !can_press_card() {return}
	card_press = {
		active  = true,
		pointer = pointer,
		started = now,
		page    = page,
		index   = selected,
	}
}

valid_card_press :: proc() -> bool {
	return can_press_card() && card_press.page == page && card_press.index == selected
}

finish_card_press :: proc(pointer: bool, now: u64) {
	if !card_press.active || card_press.pointer != pointer {return}
	card_press.active = false
	if !valid_card_press() {return}
	if now - card_press.started >= CARD_HOLD_MS {open_card_menu()} else {open_selected()}
}

poll_card_press :: proc(now: u64) {
	if !card_press.active {return}
	if !valid_card_press() {card_press.active = false; return}
	if now - card_press.started < CARD_HOLD_MS {return}
	card_press.active = false
	open_card_menu()
}

close_card_menu :: proc() {
	card_press.active = false
	card_menu = false
	card_menu_waiting = false
	card_menu_error = ""
	card_menu_revision += 1
	model.card_actions_destroy(&card_menu_actions)
	dirty = true
}

open_card_menu :: proc() {
	close_card_menu()
	if selected < 0 || selected >= len(catalog.videos) {return}
	for action in catalog.videos[selected].actions {
		append(&card_menu_actions, model.card_action_clone(action))
	}
	if len(card_menu_actions) == 0 {notice = "no actions available for this card"; return}
	card_menu = true
	card_menu_selected = 0
}

activate_card_action :: proc() {
	if card_menu_waiting ||
	   card_menu_selected < 0 ||
	   card_menu_selected >= len(card_menu_actions) {return}
	action := card_menu_actions[card_menu_selected]
	switch action.kind {
	case .Browse:
		// start_browse clones this ID before clearing the catalog and popup.
		start_browse(action.target)
	case .Edit_Playlist, .Feedback, .Playlists:
		if !signed_in {close_card_menu(); start_login(); return}
		card_menu_waiting = true
		card_menu_error = ""
		if !submit_network(
			{
				kind = .Card_Action,
				page = page,
				index = card_menu_revision,
				action = model.card_action_clone(action),
			},
		) {
			card_menu_waiting = false
			card_menu_error = "could not send action; try again"
		}
	}
	dirty = true
}

card_menu_key :: proc(code: sdl.Keycode) {
	if code == sdl.K_ESCAPE || code == sdl.K_AC_BACK {close_card_menu(); return}
	if card_menu_waiting {return}
	switch code {
	case sdl.K_UP:
		card_menu_selected = max(0, card_menu_selected - 1)
	case sdl.K_DOWN:
		card_menu_selected = min(len(card_menu_actions) - 1, card_menu_selected + 1)
	case sdl.K_RETURN, sdl.K_KP_ENTER, sdl.K_SPACE:
		activate_card_action()
	}
	dirty = true
}

card_menu_pointer :: proc(activate: bool) {
	if card_menu_waiting {
		if activate && !clay.PointerOver(clay.ID("card-menu")) {close_card_menu()}
		return
	}
	for _, i in card_menu_actions {
		if clay.PointerOver(clay.ID("card-action", u32(i))) {
			card_menu_selected = i
			if activate {activate_card_action()}
			return
		}
	}
	if activate && !clay.PointerOver(clay.ID("card-menu")) {close_card_menu()}
}

card_action_icon :: proc(action: model.Card_Action) -> (glyph: Icon) {
	switch action.kind {
	case .Browse:
		glyph = .Account
	case .Playlists:
		glyph = .Playlists
	case .Edit_Playlist:
		glyph = action.target == "WL" ? .Watch_Later : .Playlists
	case .Feedback:
		glyph = .Slower
	}
	return
}

card_menu_layout :: proc() {
	if clay.UI(clay.ID("card-menu-scrim"))(
	{
		layout = {
			sizing = {
				width = clay.SizingFixed(view_width),
				height = clay.SizingFixed(view_height),
			},
		},
		backgroundColor = {0, 0, 0, 160},
		floating = {attachTo = .Root, zIndex = 10},
	},
	) {}
	if clay.UI(clay.ID("card-menu"))(
	{
		layout = {
			sizing = {
				width = clay.SizingFit({max = min(scaled(720), view_width - scaled(64))}),
				height = clay.SizingFit({max = view_height - scaled(64)}),
			},
			layoutDirection = .TopToBottom,
			padding = clay.PaddingAll(spacing(20)),
			childGap = spacing(12),
		},
		backgroundColor = COLOR_SURFACE,
		cornerRadius = clay.CornerRadiusAll(scaled(24)),
		floating = {
			attachTo = .Root,
			attachment = {element = .CenterCenter, parent = .CenterCenter},
			zIndex = 11,
		},
	},
	) {
		if card_menu_waiting {
			if clay.UI()(
			{
				layout = {
					sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(scaled(48))},
					childAlignment = {x = .Center, y = .Center},
				},
			},
			) {icon(.Spinner, 32)}
		}
		if card_menu_error != "" {label(card_menu_error, .Small, COLOR_MUTED)}
		if clay.UI(clay.ID("card-menu-scroll"))(
		{
			layout = {
				sizing = {
					width = clay.SizingGrow({}),
					height = clay.SizingFit({max = max(scaled(72), view_height - scaled(192))}),
				},
				layoutDirection = .TopToBottom,
				childGap = spacing(4),
			},
			clip = {vertical = true, childOffset = clay.GetScrollOffset()},
		},
		) {
			for action, i in card_menu_actions {
				if clay.UI(clay.ID("card-action", u32(i)))(
				{
					layout = {
						sizing = {
							width = clay.SizingGrow({}),
							height = clay.SizingFixed(scaled(72)),
						},
						padding = padding(16, 16, 8, 8),
						childGap = spacing(16),
						childAlignment = {y = .Center},
					},
					backgroundColor = i == card_menu_selected ? COLOR_TRACK : COLOR_SURFACE,
					cornerRadius = clay.CornerRadiusAll(scaled(12)),
				},
				) {
					icon(card_action_icon(action), 32)
					label(action.label, .Small, card_menu_waiting ? COLOR_MUTED : COLOR_TEXT)
				}
			}
		}
	}
}
