package main

import clay "../vendor/clay"
import sdl "vendor:sdl3"

Navigation :: enum {
	Account,
	Search,
	Subscriptions,
	Watch_Later,
	Home,
	Playlists,
	Liked,
}
NAV_ICONS := [Navigation]Icon {
	.Account       = .Account,
	.Search        = .Search,
	.Subscriptions = .Subscriptions,
	.Watch_Later   = .Watch_Later,
	.Home          = .Home,
	.Playlists     = .Playlists,
	.Liked         = .Liked,
}
NAV_BROWSE_IDS := [Navigation]string {
	.Account       = "",
	.Search        = "",
	.Home          = "FEwhat_to_watch",
	.Subscriptions = "FEsubscriptions",
	.Playlists     = "FEplaylist_aggregation",
	.Liked         = "VLLL",
	.Watch_Later   = "VLWL",
}
browse_id: string
rail_focus: bool
rail_cursor: Navigation = .Search
rail_active: Navigation = .Search

reload_feed :: proc() {
	if browse_id != "" {
		start_browse(browse_id, browse_params, browse_filter, false)
	} else if rail_active == .Search {
		if catalog.query != "" {start_search(catalog.query)} else {start_search()}
	} else {
		start_browse(NAV_BROWSE_IDS[rail_active])
	}
}

activate_navigation :: proc(item: Navigation, window: ^sdl.Window = nil) {
	rail_cursor = item
	switch item {
	case .Account:
		if search_editing {finish_search_input(window)}
		if signed_in {
			account_menu_selected = max(0, auth_active)
			account_menu = true
		} else {start_login()}
	case .Search:
		edit_search(window)
	case .Subscriptions, .Watch_Later, .Home, .Playlists, .Liked:
		if search_editing {finish_search_input(window)}
		if item != .Home && !signed_in {start_login(); return}
		rail_active = item
		clear_browse_history()
		start_browse(NAV_BROWSE_IDS[item], remember = false)
	}
	dirty = true
}

navigation_key :: proc(code: sdl.Keycode, window: ^sdl.Window) -> bool {
	if !rail_focus {
		if code == sdl.K_LEFT && selected % grid_columns == 0 {
			rail_focus = true
			rail_cursor = rail_active
			dirty = true
			return true
		}
		return false
	}
	switch code {
	case sdl.K_UP:
		rail_cursor = Navigation(max(0, int(rail_cursor) - 1))
	case sdl.K_DOWN:
		rail_cursor = Navigation(min(int(Navigation.Liked), int(rail_cursor) + 1))
	case sdl.K_RIGHT:
		rail_focus = false
		channel_focus = len(catalog.channel.tabs) > 0
		library_focus_pending = true
	case sdl.K_RETURN, sdl.K_SPACE, sdl.K_KP_ENTER:
		activate_navigation(rail_cursor, window)
	case sdl.K_ESCAPE, sdl.K_AC_BACK:
		running = false
	case:
		return false
	}
	dirty = true
	return true
}

navigation_layout :: proc() {
	if clay.UI(clay.ID("navigation"))(
	{
		layout = {
			sizing = {width = clay.SizingFixed(scaled(128)), height = clay.SizingGrow({})},
			layoutDirection = .TopToBottom,
			padding = padding(24, 24, 32, 32),
			childGap = spacing(20),
			childAlignment = {x = .Center},
		},
		backgroundColor = COLOR_BACKGROUND,
	},
	) {
		for item in Navigation {
			focused := rail_focus && rail_cursor == item
			active := rail_active == item
			hover := clay.PointerOver(clay.ID("navigation-item", u32(item)))
			if clay.UI(clay.ID("navigation-item", u32(item)))(
			{
				layout = {
					sizing = {
						width = clay.SizingFixed(scaled(72)),
						height = clay.SizingFixed(scaled(72)),
					},
					padding = clay.PaddingAll(spacing(3)),
					childAlignment = {x = .Center, y = .Center},
				},
				backgroundColor = focused ? COLOR_ACCENT : clay.Color{},
				cornerRadius = clay.CornerRadiusAll(scaled(36)),
			},
			) {
				if clay.UI()(
				{
					layout = {
						sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
						childAlignment = {x = .Center, y = .Center},
					},
					backgroundColor = hover || active || focused ? COLOR_SURFACE : COLOR_BACKGROUND,
					cornerRadius = clay.CornerRadiusAll(scaled(33)),
				},
				) {
					if item == .Account {account_button(true)} else {icon(NAV_ICONS[item], 32)}
				}
			}
		}
	}
}
