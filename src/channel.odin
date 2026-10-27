package main

import clay "../vendor/clay"
import "./model"
import "core:strings"
import sdl "vendor:sdl3"

channel_avatar: ^sdl.Texture
channel_focus: bool
channel_cursor: int
browse_params, browse_filter: string
restore_selected: int = -1

Browse_Location :: struct {
	id, query, params, filter: string,
	selected:                  int,
}
browse_history: [dynamic]Browse_Location

free_browse_location :: proc(location: ^Browse_Location) {
	delete(location.id); delete(location.query); delete(location.params); delete(location.filter)
	location^ = {}
}

clear_browse_history :: proc() {
	for &location in browse_history {free_browse_location(&location)}
	delete(browse_history)
	browse_history = nil
}

remember_browse :: proc() {
	append(
		&browse_history,
		Browse_Location {
			id = strings.clone(browse_id),
			query = strings.clone(catalog.query),
			params = strings.clone(browse_params),
			filter = strings.clone(browse_filter),
			selected = selected,
		},
	)
}

browse_back :: proc() -> bool {
	if len(browse_history) == 0 {return false}
	location := pop(&browse_history)
	defer free_browse_location(&location)
	if location.id == "" {start_search(location.query, true)} else {
		start_browse(location.id, location.params, location.filter, false)
	}
	restore_selected = location.selected
	return true
}

activate_channel_option :: proc(index: int) {
	if search_loading {return}
	tabs := len(catalog.channel.tabs)
	if index < 0 || index >= tabs + len(catalog.channel.sorts) {return}
	if index < tabs {
		option := catalog.channel.tabs[index]
		if option.selected && notice == "" {return}
		start_browse(browse_id, option.params, "", false)
	} else {
		sort_index := index - tabs
		option := catalog.channel.sorts[sort_index]
		if option.selected && notice == "" {return}
		for &sort, i in catalog.channel.sorts {sort.selected = i == sort_index}
		start_browse(browse_id, browse_params, option.token, false)
	}
	channel_focus = true
	channel_cursor = index
}

channel_key :: proc(code: sdl.Keycode) -> bool {
	count := len(catalog.channel.tabs) + len(catalog.channel.sorts)
	if count == 0 {return false}
	if !channel_focus {
		if code != sdl.K_UP || selected >= grid_columns {return false}
		channel_focus = true
		channel_cursor = clamp(channel_cursor, 0, count - 1)
	} else {
		switch code {
		case sdl.K_LEFT:
			if channel_cursor == 0 {
				channel_focus = false
				rail_focus = true
				rail_cursor = rail_active
			} else {channel_cursor -= 1}
		case sdl.K_RIGHT:
			channel_cursor = min(count - 1, channel_cursor + 1)
		case sdl.K_DOWN:
			channel_focus = false
			library_focus_pending = true
		case sdl.K_RETURN, sdl.K_KP_ENTER, sdl.K_SPACE:
			activate_channel_option(channel_cursor)
		case:
			return false
		}
	}
	dirty = true
	return true
}

channel_pointer :: proc(activate: bool) -> bool {
	count := len(catalog.channel.tabs) + len(catalog.channel.sorts)
	for i in 0 ..< count {
		if !clay.PointerOver(clay.ID("channel-option", u32(i))) {continue}
		channel_focus = true
		rail_focus = false
		channel_cursor = i
		if activate {activate_channel_option(i)}
		return true
	}
	return false
}

channel_option :: proc(option: model.Channel_Option, index: int) {
	focused := channel_focus && channel_cursor == index
	if clay.UI(clay.ID("channel-option", u32(index)))(
	{
		layout = {
			sizing = {height = clay.SizingFixed(scaled(56))},
			padding = padding(16, 16, 8, 8),
			childAlignment = {x = .Center, y = .Center},
		},
		backgroundColor = focused ? COLOR_ACCENT : clay.PointerOver(clay.ID("channel-option", u32(index))) ? COLOR_HOVER : option.selected ? COLOR_TRACK : COLOR_SURFACE,
		cornerRadius = clay.CornerRadiusAll(scaled(12)),
	},
	) {label(option.label, .Small)}
}

channel_layout :: proc() {
	channel := catalog.channel
	if channel.title == "" {return}
	if clay.UI(clay.ID("channel-header"))(
	{
		layout = {
			sizing = {width = clay.SizingGrow({})},
			layoutDirection = .TopToBottom,
			childGap = spacing(20),
		},
	},
	) {
		if clay.UI()(
		{
			layout = {
				sizing = {width = clay.SizingGrow({})},
				childGap = spacing(24),
				childAlignment = {y = .Center},
			},
		},
		) {
			if clay.UI()(
			{
				layout = {
					sizing = {
						width = clay.SizingFixed(scaled(96)),
						height = clay.SizingFixed(scaled(96)),
					},
				},
				image = {imageData = rawptr(channel_avatar)},
				backgroundColor = COLOR_SURFACE,
				cornerRadius = clay.CornerRadiusAll(scaled(48)),
			},
			) {}
			if clay.UI()(
			{
				layout = {
					sizing = {width = clay.SizingGrow({})},
					layoutDirection = .TopToBottom,
					childGap = spacing(8),
				},
				clip = {horizontal = true},
			},
			) {
				label(channel.title, .Heading)
				if channel.meta != "" {label(channel.meta, .Small, COLOR_MUTED)}
			}
		}
		if clay.UI()(
		{
			layout = {
				sizing = {width = clay.SizingGrow({})},
				childGap = spacing(12),
				childAlignment = {y = .Center},
			},
		},
		) {
			for tab, i in channel.tabs {channel_option(tab, i)}
			if clay.UI()({layout = {sizing = {width = clay.SizingGrow({})}}}) {}
			for sort, i in channel.sorts {channel_option(sort, len(channel.tabs) + i)}
		}
	}
}
