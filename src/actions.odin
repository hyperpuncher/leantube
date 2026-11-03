package main

import "./model"
import "core:strings"
import sdl "vendor:sdl3"

key :: proc(code: sdl.Keycode, window: ^sdl.Window = nil) {
	if card_menu {card_menu_key(code); return}
	if account_menu {
		add := len(auth_accounts) < MAX_ACCOUNTS
		last := len(auth_accounts) + int(add)
		switch code {
		case sdl.K_ESCAPE, sdl.K_AC_BACK:
			account_menu = false
		case sdl.K_UP:
			account_menu_selected = max(0, account_menu_selected - 1)
		case sdl.K_DOWN:
			account_menu_selected = min(last, account_menu_selected + 1)
		case sdl.K_RETURN, sdl.K_KP_ENTER, sdl.K_SPACE:
			if account_menu_selected < len(auth_accounts) {
				activate_account(account_menu_selected)
			} else if add && account_menu_selected == len(auth_accounts) {
				account_menu = false
				start_login(true)
			} else {
				sign_out()
			}
		}
		dirty = true
		return
	}
	if login_screen {
		switch code {
		case sdl.K_ESCAPE, sdl.K_AC_BACK:
			leave_login(window)
		case sdl.K_UP, sdl.K_DOWN, sdl.K_TAB:
			if login_failed() {login_retry_selected = !login_retry_selected}
		case sdl.K_RETURN, sdl.K_KP_ENTER, sdl.K_SPACE:
			if login_retry_selected {retry_login()} else {leave_login(window)}
		}
		dirty = true
		return
	}
	if browsing && !search_editing {
		if (code == sdl.K_ESCAPE || code == sdl.K_AC_BACK) && browse_back() {return}
		if !rail_focus && channel_key(code) {return}
		if navigation_key(code, window) {return}
	}
	if browsing && search_key(code, window) {return}
	if browsing {
		library_focus_pending = true
		switch code {
		case sdl.K_ESCAPE, sdl.K_AC_BACK:
			if rail_active == .Playlists && strings.has_prefix(browse_id, "VL") {
				start_browse(NAV_ITEMS[.Playlists].browse_id)
			}
		case sdl.K_RETURN, sdl.K_SPACE, sdl.K_KP_ENTER:
			open_selected()
		case sdl.K_LEFT:
			selected = model.grid_move(selected, len(catalog.videos), -1, 0, grid_columns)
		case sdl.K_RIGHT:
			selected = model.grid_move(selected, len(catalog.videos), 1, 0, grid_columns)
		case sdl.K_UP:
			selected = model.grid_move(selected, len(catalog.videos), 0, -1, grid_columns)
		case sdl.K_DOWN:
			selected = model.grid_move(selected, len(catalog.videos), 0, 1, grid_columns)
		}
	} else {
		show_player_controls()
		switch code {
		case sdl.K_ESCAPE, sdl.K_AC_BACK:
			return_to_grid = true
		case sdl.K_RETURN, sdl.K_SPACE, sdl.K_KP_ENTER:
			_ = player_pause(!paused)
		case sdl.K_MEDIA_PLAY:
			_ = player_pause(false)
		case sdl.K_MEDIA_PAUSE:
			_ = player_pause(true)
		case sdl.K_LEFT, sdl.K_RIGHT:
			offset: f64 = code == sdl.K_RIGHT ? 10000 : -10000
			target := model.seek_target(timeline, offset, duration_ms)
			seek_to(target)
		case sdl.K_UP, sdl.K_DOWN:
			delta: f64 = code == sdl.K_DOWN ? -0.25 : 0.25
			next := clamp(rate + delta, 0.5, 2)
			if next != rate && player_rate(next) {rate = next}
		}
	}
	dirty = true
}
