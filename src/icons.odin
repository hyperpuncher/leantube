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
	Slower,
	Faster,
	Account,
	Search,
	Subscriptions,
	Watch_Later,
	Home,
	Playlists,
	Liked,
	Spinner,
}
ICON_FILES :: [Icon]string {
	.Play          = "play",
	.Pause         = "pause",
	.Slower        = "minus",
	.Faster        = "plus",
	.Account       = "user-round",
	.Search        = "search",
	.Subscriptions = "gallery-vertical-end",
	.Watch_Later   = "clock",
	.Home          = "house",
	.Playlists     = "list-video",
	.Liked         = "thumbs-up",
	.Spinner       = "loader",
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

// Float in the center without changing the parent's content layout.
centered_spinner :: proc() {
	if clay.UI()(
	{
		floating = {
			attachTo = .Parent,
			attachment = {element = .CenterCenter, parent = .CenterCenter},
			pointerCaptureMode = .Passthrough,
		},
	},
	) {icon(.Spinner)}
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
