package main

import clay "../vendor/clay"
import "core:c"
import "core:fmt"
import "core:math"
import sdl "vendor:sdl3"
import img "vendor:sdl3/image"

Icon :: enum {
	Play,
	Pause,
	Seek_Back,
	Seek_Forward,
	Slower,
	Faster,
	Account,
	Search,
	Subscriptions,
	Home,
	Playlists,
	Liked,
}
ICON_FILES :: [Icon]string {
	.Play          = "play",
	.Pause         = "pause",
	.Seek_Back     = "rotate-ccw",
	.Seek_Forward  = "rotate-cw",
	.Slower        = "minus",
	.Faster        = "plus",
	.Account       = "user-round",
	.Search        = "search",
	.Subscriptions = "gallery-vertical-end",
	.Home          = "house",
	.Playlists     = "list-video",
	.Liked         = "thumbs-up",
}
icons: [Icon]^sdl.Texture
icon_pixels: c.int

load_texture :: proc(renderer: ^sdl.Renderer, path: cstring) -> ^sdl.Texture {
	texture := img.LoadTexture(renderer, path)
	if texture == nil {return nil}
	// Opaque covers need blending for the rounded edge coverage.
	if !sdl.SetTextureBlendMode(texture, sdl.BLENDMODE_BLEND) ||
	   !sdl.SetTextureScaleMode(texture, .LINEAR) {
		sdl.DestroyTexture(texture)
		return nil
	}
	return texture
}

open_icons :: proc(renderer: ^sdl.Renderer) -> bool {
	pixels := c.int(math.ceil(scaled(48)))
	if icon_pixels == pixels {return true}
	close_icons()
	for file, i in ICON_FILES {
		path := fmt.caprintf("%s/icons/%s.svg", app_directory, file)
		stream := sdl.IOFromFile(path, "rb")
		delete(path)
		if stream == nil {return false}
		surface := img.LoadSizedSVG_IO(stream, pixels, pixels)
		_ = sdl.CloseIO(stream)
		if surface == nil {return false}
		icons[i] = sdl.CreateTextureFromSurface(renderer, surface)
		sdl.DestroySurface(surface)
		if icons[i] == nil {return false}
	}
	icon_pixels = pixels
	return true
}

close_icons :: proc() {
	for texture in icons {if texture != nil {sdl.DestroyTexture(texture)}}
	icons = {}
	icon_pixels = 0
}

icon :: proc(id: Icon, size: f32 = 48) {
	if clay.UI()(
	{
		layout = {
			sizing = {
				width = clay.SizingFixed(scaled(size)),
				height = clay.SizingFixed(scaled(size)),
			},
		},
		image = {imageData = rawptr(icons[id])},
	},
	) {}
}
