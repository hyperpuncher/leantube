package main

import clay "../vendor/clay"
import sdl "vendor:sdl3"

Navigation :: enum {
	Account,
	Search,
	Subscriptions,
	Watch_Later,
	History,
	Home,
	Playlists,
	Liked,
}
NAV_ITEMS := [Navigation]struct {
	icon:             Icon,
	label, browse_id: string,
} {
	.Account       = {.Account, "Account", ""},
	.Search        = {.Search, "Search", ""},
	.Subscriptions = {.Subscriptions, "Subscriptions", "FEsubscriptions"},
	.Watch_Later   = {.Watch_Later, "Watch later", "VLWL"},
	.History       = {.History, "History", "FEhistory"},
	.Home          = {.Home, "Home", "FEwhat_to_watch"},
	.Playlists     = {.Playlists, "Playlists", "FEplaylist_aggregation"},
	.Liked         = {.Liked, "Liked videos", "VLLL"},
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
		start_browse(NAV_ITEMS[rail_active].browse_id)
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
	case .Subscriptions, .Watch_Later, .History, .Home, .Playlists, .Liked:
		if search_editing {finish_search_input(window)}
		if !signed_in {start_login(); return}
		rail_active = item
		clear_browse_history()
		start_browse(NAV_ITEMS[item].browse_id, remember = false)
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
		rail_focus = false
	case:
		return false
	}
	dirty = true
	return true
}

navigation_layout :: proc() {
	// Keep full-size icons; reduce only the gaps on shorter screens.
	gap := clamp(
		(view_height - scaled(64 + 72 * len(NAV_ITEMS))) / f32(len(NAV_ITEMS) - 1),
		0,
		scaled(20),
	)
	if clay.UI(clay.ID("navigation"))(
	{
		layout = {
			sizing = {width = clay.SizingFixed(scaled(128)), height = clay.SizingGrow({})},
			layoutDirection = .TopToBottom,
			padding = padding(24, 24, 32, 32),
			childGap = u16(gap),
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
					if item ==
					   .Account {account_button(true)} else {icon(NAV_ITEMS[item].icon, 32)}
				}
				if (focused || hover) && !account_menu && !card_menu {
					if clay.UI(clay.ID("navigation-tooltip", u32(item)))(
					{
						layout = {padding = padding(16, 16, 8, 8)},
						backgroundColor = COLOR_HOVER,
						cornerRadius = clay.CornerRadiusAll(scaled(8)),
						floating = {
							attachTo = .Parent,
							attachment = {element = .LeftCenter, parent = .RightCenter},
							offset = {scaled(16), 0},
							zIndex = 5,
							pointerCaptureMode = .Passthrough,
						},
					},
					) {label(NAV_ITEMS[item].label, .Small)}
				}
			}
		}
	}
}
