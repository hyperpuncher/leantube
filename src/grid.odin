package main

import clay "../vendor/clay"
import "./model"
import "core:c"
import "core:math"
import "core:strings"
import sdl "vendor:sdl3"

library_focus_pending := true

// Clay tracks every clipped element, and its container table is small, so the
// grid must not clip each caption. Labels are fitted to the measured card width
// instead, once per catalog or width change, and drawn without clipping.
Card_Label :: struct {
	title, channel, meta: string,
	title_lines:          int,
}
// Like image slots, fitted labels use the original feed index, not display order.
card_labels: [dynamic]Card_Label
card_labels_revision := -1
card_labels_width: f32
card_labels_scale: f32
// Row starts include the scroll leading inset; the last entry is the total height.
row_offsets: [dynamic]f32
row_heights: [dynamic]f32
row_revision := -1
row_columns: int
row_width: f32
row_scale: f32

labels_release :: proc() {
	for &label in card_labels {delete(label.title); delete(label.channel); delete(label.meta)}
	clear(&card_labels)
	card_labels_revision = -1
}

labels_build :: proc(metrics: Grid_Metrics) {
	width := metrics.text_width
	if card_labels_scale != ui_scale ||
	   math.abs(width - card_labels_width) >= 0.5 {labels_release()}
	first_cover := len(card_labels)
	resize(&card_labels, len(textures))
	for video in catalog.videos {
		if video.cover_index < first_cover {continue}
		title, title_owned, title_lines := fit_wrapped(fonts[.Small], video.title, c.int(width), 2)
		channel_width :=
			width - (model.video_channel_id(video) != "" ? scaled(CARD_AVATAR_SIZE + 16) : 0)
		channel, channel_owned := fit_text(fonts[.Caption], video.channel, c.int(channel_width))
		meta, meta_owned := fit_text(fonts[.Caption], video.meta, c.int(width))
		card_labels[video.cover_index] = {
			title       = title_owned ? title : strings.clone(title),
			channel     = channel_owned ? channel : strings.clone(channel),
			meta        = meta_owned ? meta : strings.clone(meta),
			title_lines = title_lines,
		}
	}
	card_labels_width = width
	card_labels_scale = ui_scale
	card_labels_revision = catalog_revision
	rows_build(metrics)
}

// Row heights follow their tallest card, so one-line rows do not reserve empty lines.
rows_build :: proc(metrics: Grid_Metrics) {
	rows := grid_rows(len(catalog.videos), grid_columns)
	clear(&row_offsets)
	clear(&row_heights)
	resize(&row_heights, rows)
	for video, index in catalog.videos {
		row := index / grid_columns
		row_heights[row] = max(row_heights[row], card_height(metrics, card_shape(video)))
	}
	resize(&row_offsets, rows + 1)
	cursor := metrics.leading
	for height, row in row_heights {
		row_offsets[row] = cursor
		cursor += height + metrics.gap
	}
	row_offsets[rows] = max(0, cursor - metrics.gap)
	row_revision = catalog_revision
	row_columns = grid_columns
	row_width = metrics.card_width
	row_scale = ui_scale
}

// What a card draws below the cover. Row heights and the card itself share it.
Card_Shape :: struct {
	lines:   int,
	channel: bool,
	meta:    bool,
}

card_shape :: proc(video: model.Video) -> Card_Shape {
	shape := Card_Shape {
		lines   = 1,
		channel = model.video_channel_id(video) != "",
	}
	if video.cover_index < len(card_labels) {
		label := card_labels[video.cover_index]
		shape.lines = max(1, label.title_lines)
		shape.meta = label.meta != ""
	}
	return shape
}

grid_rows_ready :: proc(metrics: Grid_Metrics) -> bool {
	return(
		row_revision == catalog_revision &&
		row_columns == grid_columns &&
		row_scale == ui_scale &&
		math.abs(row_width - metrics.card_width) < 0.5 \
	)
}

// Fit only new cards. The fixed card width is known before layout.
grid_labels :: proc(metrics: Grid_Metrics) {
	if len(catalog.videos) == 0 {labels_release(); return}
	if card_labels_revision == catalog_revision &&
	   card_labels_scale == ui_scale &&
	   math.abs(metrics.text_width - card_labels_width) < 0.5 {return}
	labels_build(metrics)
}

list_spacer :: proc(height: f32) {
	if height <= 0 {return}
	if clay.UI()(
	{layout = {sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(height)}}},
	) {}
}

// Rows wholly outside the viewport stay out of layout. Spacers keep the full
// scroll height, and one extra row on each side prevents blank edges.
visible_rows :: proc() -> (first, last: int) {
	rows := len(row_heights)
	top, height: f32
	scroll := clay.GetScrollContainerData(clay.ID("library-scroll"))
	if scroll.found && scroll.scrollPosition != nil {
		top = max(0, -scroll.scrollPosition.y)
		height = scroll.scrollContainerDimensions.height
	}
	// Before the first layout, overestimate from the display instead of
	// laying out every row or leaving the lower viewport empty.
	if height <= 0 {height = view_height}
	first = max(0, row_at(top) - 1)
	last = min(rows, row_at(top + height) + 1)
	return
}

// First row whose bottom edge is below the content position.
row_at :: proc(position: f32) -> int {
	low, high := 0, len(row_heights)
	for low < high {
		middle := (low + high) / 2
		if row_offsets[middle] + row_heights[middle] <= position {
			low = middle + 1
		} else {
			high = middle
		}
	}
	return low
}

grid_layout :: proc() {
	metrics := grid_metrics()
	grid_labels(metrics)
	if !grid_rows_ready(metrics) {rows_build(metrics)}
	if clay.UI(clay.ID("grid-root"))(
	{
		layout = {
			sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
			layoutDirection = .LeftToRight,
		},
		backgroundColor = COLOR_BACKGROUND,
	},
	) {
		navigation_layout()
		if clay.UI(clay.ID("library-content"))(
		{
			layout = {
				sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
				layoutDirection = .TopToBottom,
				padding = padding(32, 48, 0, 0),
				childGap = spacing(16),
			},
		},
		) {
			if search_editing {search_layout()}
			channel_layout()
			if search_loading && len(catalog.videos) == 0 {centered_spinner()}
			if clay.UI(clay.ID("library-scroll"))(
			{
				layout = {
					sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
					layoutDirection = .TopToBottom,
					childGap = u16(metrics.gap),
				},
				clip = {vertical = true, childOffset = clay.GetScrollOffset()},
			},
			) {
				rows := len(row_heights)
				first, last := visible_rows()
				list_spacer(row_offsets[first] - metrics.gap)
				for row in first ..< last {
					if clay.UI()(
					{
						layout = {
							sizing = {
								width = clay.SizingGrow({}),
								height = clay.SizingFixed(row_heights[row]),
							},
							childGap = u16(metrics.gap),
						},
					},
					) {
						for column in 0 ..< grid_columns {
							index := row * grid_columns + column
							if index < len(catalog.videos) {
								video_card(index, metrics)
							} else if clay.UI()(
							{layout = {sizing = {width = clay.SizingFixed(metrics.card_width)}}},
							) {}
						}
					}
				}
				if last < rows {
					// The trailing gap is already part of row_offsets[rows].
					list_spacer(row_offsets[rows] - row_offsets[last])
				}
			}
		}
		if account_menu {account_menu_layout()}
		if card_menu {card_menu_layout()}
	}
}

video_card :: proc(index: int, metrics: Grid_Metrics) {
	video := catalog.videos[index]
	shape := card_shape(video)
	corners := clay.CornerRadiusAll(scaled(12))
	// The chip pads a line box, not the digits, so lift their ink instead.
	chip_top := u16(max(0, i32(spacing(4)) - digit_ink_shift[.Caption]))
	chip_bottom := u16(i32(spacing(4)) + digit_ink_shift[.Caption])
	title, channel, meta := video.title, video.channel, video.meta
	if video.cover_index < len(card_labels) {
		title = card_labels[video.cover_index].title
		channel = card_labels[video.cover_index].channel
		meta = card_labels[video.cover_index].meta
	}
	focus :=
		!rail_focus && !channel_focus && !search_editing && index == selected ? COLOR_HOVER : clay.PointerOver(clay.ID("video", u32(index))) ? COLOR_SURFACE : clay.Color{}
	if clay.UI(clay.ID("video", u32(index)))(
	{
		layout = {
			sizing = {
				width = clay.SizingFixed(metrics.card_width),
				height = clay.SizingFixed(card_height(metrics, shape)),
			},
			layoutDirection = .TopToBottom,
			padding = clay.PaddingAll(u16(metrics.padding)),
			childGap = u16(metrics.card_gap),
		},
		backgroundColor = focus,
		cornerRadius = clay.CornerRadiusAll(scaled(16)),
	},
	) {
		if clay.UI(clay.ID("cover", u32(index)))(
		{
			layout = {sizing = {width = clay.SizingGrow({})}},
			image = {imageData = rawptr(textures[video.cover_index])},
			backgroundColor = textures[video.cover_index] == nil ? COLOR_SURFACE : clay.Color{},
			aspectRatio = {16.0 / 9.0},
			cornerRadius = corners,
		},
		) {
			if video.id != "" &&
			   video.browse_id == "" &&
			   clay.PointerOver(clay.ID("video", u32(index))) {
				id := clay.ID("watch-later", u32(index))
				color := clay.PointerOver(id) ? COLOR_HOVER : COLOR_BADGE
				color[3] = COLOR_BADGE[3]
				if clay.UI(id)(
				{
					layout = {
						sizing = {
							width = clay.SizingFixed(scaled(48)),
							height = clay.SizingFixed(scaled(48)),
						},
						childAlignment = {x = .Center, y = .Center},
					},
					backgroundColor = color,
					cornerRadius = clay.CornerRadiusAll(scaled(8)),
					floating = {
						attachTo = .Parent,
						attachment = {element = .RightTop, parent = .RightTop},
						offset = {-scaled(8), scaled(8)},
						clipTo = .AttachedParent,
						zIndex = 1,
						pointerCaptureMode = .Passthrough,
					},
				},
				) {
					glyph: Icon = video.watch_later == .Present ? .Watch_Later_Saved : .Watch_Later
					if video.cover_index == card_action_cover {
						if card_menu_waiting {glyph = .Spinner} else if card_action_done_until > sdl.GetTicks() {glyph = .Check}
					}
					icon(glyph, 32)
				}
			}
			if clay.UI(clay.ID("duration", u32(index)))(
			{
				floating = {
					attachTo = .Parent,
					attachment = {element = .RightBottom, parent = .RightBottom},
					offset = {-scaled(8), -scaled(8)},
					clipTo = .AttachedParent,
					pointerCaptureMode = .Passthrough,
				},
				layout = {padding = {spacing(8), spacing(8), chip_top, chip_bottom}},
				backgroundColor = COLOR_BADGE,
				cornerRadius = clay.CornerRadiusAll(scaled(4)),
			},
			) {label(video.duration_label, .Caption)}
			if video.watched_percent > 0 {
				if clay.UI(clay.ID("watched-progress", u32(index)))(
				{
					floating = {
						attachTo = .Parent,
						clipTo = .AttachedParent,
						pointerCaptureMode = .Passthrough,
					},
					layout = {
						sizing = {width = clay.SizingPercent(1), height = clay.SizingPercent(1)},
					},
					cornerRadius = corners,
					custom = {customData = &catalog.videos[index].watched_percent},
				},
				) {}
			}
		}
		if clay.UI()(
		{
			layout = {
				sizing = {width = clay.SizingGrow({})},
				layoutDirection = .TopToBottom,
				childGap = u16(metrics.text_gap),
			},
		},
		) {
			if clay.UI(clay.ID("card-title", u32(index)))(
			{
				layout = {
					sizing = {
						width = clay.SizingGrow({}),
						height = clay.SizingFixed(f32(shape.lines) * metrics.line),
					},
				},
			},
			) {label(title, .Small, wrap = .Words)}
			if clay.UI(clay.ID("card-channel", u32(index)))(
			{
				layout = {
					sizing = {
						width = clay.SizingGrow({}),
						height = clay.SizingFixed(shape.channel ? metrics.channel : metrics.meta),
					},
					childGap = spacing(8),
					childAlignment = {y = .Center},
				},
			},
			) {
				if shape.channel {
					avatar_button(
						clay.ID("card-avatar", u32(index)),
						card_avatars[video.cover_index],
						CARD_AVATAR_SIZE,
						4,
					)
				}
				label(channel, .Caption, COLOR_MUTED)
			}
			if shape.meta {
				if clay.UI(clay.ID("card-meta", u32(index)))(
				{
					layout = {
						sizing = {
							width = clay.SizingGrow({}),
							height = clay.SizingFixed(metrics.meta),
						},
					},
				},
				) {label(meta, .Caption, COLOR_MUTED)}
			}
		}
	}
}
