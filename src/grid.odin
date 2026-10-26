package main

import clay "../vendor/clay"
import "./model"
import "core:fmt"
import "core:os"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

library_focus_pending := true

load_catalog :: proc(renderer: ^sdl.Renderer, directory: string) -> bool {
	path := fmt.aprintf("%s/catalog.json", directory)
	defer delete(path)
	data, error := os.read_entire_file(path, context.allocator)
	if error != nil {fmt.eprintln("catalog missing; use just browse on the host"); return false}
	defer delete(data)
	parsed, ok := model.catalog_parse(string(data))
	if !ok {fmt.eprintln("invalid video catalog"); return false}
	catalog = parsed
	for _, i in catalog.videos {
		for extension in ([]string{"webp", "jpg"}) {
			name := fmt.caprintf("%s/%d.%s", directory, i, extension)
			textures[i] = load_texture(renderer, name)
			delete(name)
			if textures[i] != nil {break}
		}
		if textures[i] == nil {fmt.eprintln("thumbnail load failed:", i, sdl.GetError())}
	}
	return true
}

grid_layout :: proc() {
	if clay.UI(clay.ID("grid-root"))(
	{
		layout = {
			sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
			layoutDirection = .TopToBottom,
			padding = padding(64, 64, 32, 0),
			childGap = spacing(16),
		},
		backgroundColor = COLOR_BACKGROUND,
	},
	) {
		if clay.UI()(
		{
			layout = {
				sizing = {
					width = clay.SizingGrow({}),
					height = clay.SizingFixed(f32(ttf.GetFontHeight(fonts[.Heading]))),
				},
				padding = padding(8, 8, 0, 0),
				childAlignment = {y = .Center},
			},
			clip = {horizontal = true, vertical = true},
		},
		) {
			label(catalog.query == "" ? "Recommended" : catalog.query, .Heading)
			if notice != "" {
				if clay.UI()({layout = {sizing = {width = clay.SizingGrow({})}}}) {}
				label(notice, .Caption, COLOR_MUTED)
			}
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
									sizing = {width = clay.SizingPercent(1.0 / f32(grid_columns))},
								},
							},
							) {}
						}
					}
				}
			}
		}
	}
}

video_card :: proc(index: int) {
	video := catalog.videos[index]
	focus := index == selected ? COLOR_ACCENT : COLOR_BACKGROUND
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
			if clay.UI()(
			{
				layout = {
					sizing = {
						width = clay.SizingGrow({}),
						height = clay.SizingFit({max = f32(ttf.GetFontHeight(fonts[.Small])) * 2}),
					},
				},
				clip = {vertical = true},
			},
			) {label(video.title, .Small, wrap = .Words)}
			if clay.UI()(
			{
				layout = {
					sizing = {
						width = clay.SizingGrow({}),
						height = clay.SizingFixed(f32(ttf.GetFontHeight(fonts[.Caption]))),
					},
				},
				clip = {horizontal = true, vertical = true},
			},
			) {label(video.channel, .Caption, COLOR_MUTED)}
		}
	}
}
