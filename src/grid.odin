package main

import clay "../vendor/clay"
import "core:c"
import "core:math"
import "core:strings"
import ttf "vendor:sdl3/ttf"

library_focus_pending := true

// Clay tracks every clipped element, and its container table is small, so the
// grid must not clip each caption. Labels are fitted to the measured card width
// instead, once per catalog or width change, and drawn without clipping.
Card_Label :: struct {
	title, channel, meta: string,
}
card_labels: [dynamic]Card_Label
card_labels_revision := -1
card_labels_width: f32
card_labels_scale: f32

labels_release :: proc() {
	for &label in card_labels {delete(label.title); delete(label.channel); delete(label.meta)}
	clear(&card_labels)
	card_labels_revision = -1
}

labels_build :: proc(width: f32) {
	labels_release()
	for video in catalog.videos {
		title, title_owned := fit_wrapped(fonts[.Small], video.title, c.int(width), 2)
		channel, channel_owned := fit_text(fonts[.Caption], video.channel, c.int(width))
		meta, meta_owned := fit_text(fonts[.Caption], video.meta, c.int(width))
		append(
			&card_labels,
			Card_Label {
				title = strings.clone(title),
				channel = strings.clone(channel),
				meta = strings.clone(meta),
			},
		)
		if title_owned {delete(title)}
		if channel_owned {delete(channel)}
		if meta_owned {delete(meta)}
	}
	card_labels_width = width
	card_labels_scale = ui_scale
	card_labels_revision = catalog_revision
}

// Rebuild once the first layout reports the exact line width. Returns true when
// the caller must lay out again to draw the fitted labels.
grid_measure_labels :: proc() -> bool {
	if len(catalog.videos) == 0 {
		labels_release()
		return false
	}
	box := clay.GetElementData(clay.ID("card-title", 0)).boundingBox
	if box.width <= 0 {return false}
	if card_labels_revision == catalog_revision &&
	   card_labels_scale == ui_scale &&
	   math.abs(box.width - card_labels_width) < 0.5 {return false}
	labels_build(box.width)
	return true
}

grid_layout :: proc() {
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
				padding = padding(32, 48, 32, 0),
				childGap = spacing(16),
			},
		},
		) {
			if search_editing {search_layout()}
			if search_loading && len(catalog.videos) == 0 {centered_spinner()}
			if !search_loading && notice != "" {
				label(notice, .Small, COLOR_MUTED)
			}
			if clay.UI(clay.ID("library-scroll"))(
			{
				layout = {
					sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
					layoutDirection = .TopToBottom,
					childGap = spacing(32),
				},
				clip = {vertical = true, childOffset = clay.GetScrollOffset()},
			},
			) {
				for row in 0 ..< (len(catalog.videos) + grid_columns - 1) / grid_columns {
					if clay.UI()(
					{layout = {sizing = {width = clay.SizingGrow({})}, childGap = spacing(32)}},
					) {
						for column in 0 ..< grid_columns {
							index := row * grid_columns + column
							if index < len(catalog.videos) {
								video_card(index)
							} else {
								// Keep the final row gaps equal to those of a full row.
								if clay.UI()(
								{
									layout = {
										sizing = {
											width = clay.SizingPercent(1.0 / f32(grid_columns)),
										},
									},
								},
								) {}
							}
						}
					}
				}
				if catalog.continuation != "" {
					if clay.UI(clay.ID("load-more"))(
					{
						layout = {
							sizing = {
								width = clay.SizingGrow({}),
								height = clay.SizingFixed(scaled(64)),
							},
							childAlignment = {x = .Center, y = .Center},
						},
						backgroundColor = COLOR_SURFACE,
						cornerRadius = clay.CornerRadiusAll(scaled(12)),
					},
					) {
						if search_loading {icon(.Spinner, 32)} else {label("Load more", .Small)}
					}
				}
			}
		}
		if account_menu {account_menu_layout()}
		if card_menu {card_menu_layout()}
	}
}

video_card :: proc(index: int) {
	video := catalog.videos[index]
	title, channel, meta := video.title, video.channel, video.meta
	if index < len(card_labels) {
		title = card_labels[index].title
		channel = card_labels[index].channel
		meta = card_labels[index].meta
	}
	focus := !rail_focus && !search_editing && index == selected ? COLOR_ACCENT : COLOR_BACKGROUND
	if clay.UI(clay.ID("video", u32(index)))(
	{
		layout = {
			sizing = {width = clay.SizingPercent(1.0 / f32(grid_columns))},
			layoutDirection = .TopToBottom,
			padding = padding(4, 4, 0, 0),
			childGap = spacing(4),
		},
	},
	) {
		if clay.UI()(
		{
			layout = {
				sizing = {width = clay.SizingGrow({})},
				padding = clay.PaddingAll(spacing(4)),
			},
			backgroundColor = focus,
			cornerRadius = clay.CornerRadiusAll(scaled(16)),
		},
		) {
			if clay.UI(clay.ID("cover", u32(index)))(
			{
				layout = {sizing = {width = clay.SizingGrow({})}},
				image = {imageData = rawptr(textures[index])},
				backgroundColor = textures[index] == nil ? COLOR_SURFACE : clay.Color{},
				aspectRatio = {16.0 / 9.0},
				cornerRadius = clay.CornerRadiusAll(scaled(12)),
			},
			) {
				if clay.UI(clay.ID("duration", u32(index)))(
				{
					floating = {
						attachTo = .Parent,
						attachment = {element = .RightBottom, parent = .RightBottom},
						offset = {-scaled(8), -scaled(8)},
						clipTo = .AttachedParent,
						pointerCaptureMode = .Passthrough,
					},
					layout = {padding = padding(8, 8, 4, 4)},
					backgroundColor = COLOR_BADGE,
					cornerRadius = clay.CornerRadiusAll(scaled(4)),
				},
				) {label(video.duration_label, .Mono_Small)}
			}
		}
		if clay.UI()(
		{
			layout = {
				sizing = {width = clay.SizingGrow({})},
				layoutDirection = .TopToBottom,
				childGap = spacing(2),
				padding = padding(4, 4, 0, 0),
			},
		},
		) {
			if clay.UI(clay.ID("card-title", u32(index)))(
			{
				layout = {
					sizing = {
						width = clay.SizingGrow({}),
						height = clay.SizingFit({max = f32(ttf.GetFontHeight(fonts[.Small])) * 2}),
					},
				},
			},
			) {label(title, .Small, wrap = .Words)}
			if clay.UI(clay.ID("card-channel", u32(index)))(
			{
				layout = {
					sizing = {
						width = clay.SizingGrow({}),
						height = clay.SizingFixed(f32(ttf.GetFontHeight(fonts[.Caption]))),
					},
				},
			},
			) {label(channel, .Caption, COLOR_MUTED)}
			if meta != "" {
				if clay.UI(clay.ID("card-meta", u32(index)))(
				{
					layout = {
						sizing = {
							width = clay.SizingGrow({}),
							height = clay.SizingFixed(f32(ttf.GetFontHeight(fonts[.Caption]))),
						},
					},
				},
				) {label(meta, .Caption, COLOR_MUTED)}
			}
		}
	}
}
