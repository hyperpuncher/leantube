package main

import "./model"
import sb "./sponsorblock"
import "core:fmt"
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
			close_login_screen()
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
				start_browse(NAV_BROWSE_IDS[.Playlists])
			} else {running = false}
		case sdl.K_RETURN, sdl.K_SPACE, sdl.K_KP_ENTER:
			open_selected()
		case sdl.K_LEFT:
			selected = model.grid_move(selected, len(catalog.videos), -1, 0, grid_columns)
		case sdl.K_RIGHT:
			selected = model.grid_move(selected, len(catalog.videos), 1, 0, grid_columns)
		case sdl.K_UP:
			selected = model.grid_move(selected, len(catalog.videos), 0, -1, grid_columns)
		case sdl.K_DOWN:
			if selected / grid_columns == (len(catalog.videos) - 1) / grid_columns {load_more()}
			selected = model.grid_move(selected, len(catalog.videos), 0, 1, grid_columns)
		}
	} else {
		show_player_controls()
		switch code {
		case sdl.K_ESCAPE, sdl.K_AC_BACK:
			return_to_grid = true
		case sdl.K_RETURN, sdl.K_SPACE, sdl.K_KP_ENTER, sdl.K_MEDIA_PLAY, sdl.K_MEDIA_PAUSE:
			if paused {command("luna://com.webos.media/play")} else {command("luna://com.webos.media/pause")}
		case sdl.K_LEFT, sdl.K_RIGHT:
			offset: f64 = code == sdl.K_RIGHT ? 10000 : -10000
			target := model.seek_target(timeline, offset, duration_ms)
			seek_to(target)
		case sdl.K_UP, sdl.K_DOWN:
			delta: f64 = code == sdl.K_DOWN ? -0.25 : 0.25
			rate = clamp(rate + delta, 0.5, 2)
			extra := fmt.aprintf(",\"playRate\":%.2f,\"audioOutput\":true", rate)
			command("luna://com.webos.media/setPlayRate", extra)
			delete(extra)
		}
	}
	dirty = true
}

seek_to :: proc(target: f64) -> bool {
	extra := fmt.aprintf(",\"position\":%d", i64(target))
	defer delete(extra)
	if !command("luna://com.webos.media/seek", extra, .Seek) {return false}
	timeline.seek_target_ms = target
	return true
}

auto_skip_sponsor :: proc() {
	if browsing || !loaded || paused || timeline.seek_target_ms >= 0 {return}
	from := timeline.position_ms
	target := sb.skip_target(sponsor_segments[:], from, duration_ms)
	if target >= 0 && seek_to(target) {
		fmt.printf("sponsor skip %.3f -> %.3f seconds\n", from / 1000, target / 1000)
		sb.mark_skipped(sponsor_segments[:], from, target)
	}
}
