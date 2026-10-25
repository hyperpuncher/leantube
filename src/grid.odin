package main

import clay "../vendor/clay"
import "./model"
import "core:fmt"
import "core:os"
import sdl "vendor:sdl3"

load_catalog :: proc(renderer: ^sdl.Renderer) -> bool {
	path := fmt.aprintf("%s/catalog/catalog.json", app_directory)
	defer delete(path)
	data, error := os.read_entire_file(path, context.allocator)
	if error != nil {fmt.eprintln("catalog missing; use just browse on the host"); return false}
	defer delete(data)
	parsed, ok := model.catalog_parse(string(data))
	if !ok {fmt.eprintln("invalid video catalog"); return false}
	catalog = parsed
	for _, i in catalog.videos {
		name := fmt.caprintf("%s/catalog/%d.bmp", app_directory, i)
		surface := sdl.LoadBMP(name)
		delete(name)
		if surface == nil {
			fmt.eprintln("thumbnail load failed:", i, sdl.GetError())
			continue
		}
		textures[i] = sdl.CreateTextureFromSurface(renderer, surface)
		sdl.DestroySurface(surface)
		if textures[i] == nil {fmt.eprintln("thumbnail texture failed:", sdl.GetError())}
	}
	return true
}

grid_layout :: proc() {
	if clay.UI(clay.ID("grid-root"))(
	{
		layout = {
			sizing = {
				width = clay.SizingFixed(VIEW_WIDTH),
				height = clay.SizingFixed(VIEW_HEIGHT),
			},
			layoutDirection = .TopToBottom,
			padding = clay.PaddingAll(24),
			childGap = 12,
			childAlignment = {x = .Center},
		},
		backgroundColor = {12, 16, 24, 255},
	},
	) {
		if clay.UI()(
		{layout = {sizing = {width = clay.SizingGrow({})}, childAlignment = {y = .Center}}},
		) {
			label("LeanTube", 20)
			if clay.UI()({layout = {sizing = {width = clay.SizingGrow({})}}}) {}
			label("YouTube / prepared on host", 10, {150, 163, 185, 255})
		}
		label(catalog.query, 12, {165, 178, 198, 255})
		if clay.UI()({layout = {layoutDirection = .TopToBottom, childGap = 16}}) {
			for row in 0 ..< (len(catalog.videos) + model.GRID_COLUMNS - 1) / model.GRID_COLUMNS {
				if clay.UI()(
				{layout = {sizing = {width = clay.SizingFixed(896)}, childGap = 16}},
				) {
					for column in 0 ..< model.GRID_COLUMNS {
						index := row * model.GRID_COLUMNS + column
						if index >= len(catalog.videos) {break}
						video_card(index)
					}
				}
			}
		}
		label(notice, 10, {165, 178, 198, 255})
	}
}

video_card :: proc(index: int) {
	video := catalog.videos[index]
	color: clay.Color = {28, 35, 49, 255}
	if index == selected {color = {154, 35, 47, 255}}
	if clay.UI(clay.ID("video", u32(index)))(
	{
		layout = {
			sizing = {width = clay.SizingFixed(288), height = clay.SizingFixed(192)},
			layoutDirection = .TopToBottom,
			padding = {16, 16, 8, 8},
			childGap = 4,
		},
		backgroundColor = color,
	},
	) {
		if clay.UI()(
		{
			layout = {sizing = {width = clay.SizingFixed(256), height = clay.SizingFixed(144)}},
			image = {imageData = rawptr(textures[index])},
		},
		) {}
		label(video.title_label, 12)
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow({})}}}) {
			label(video.channel_label, 10, {180, 190, 207, 255})
			if clay.UI()({layout = {sizing = {width = clay.SizingGrow({})}}}) {}
			label(video.duration_label, 10, {180, 190, 207, 255})
		}
	}
}
