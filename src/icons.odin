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
	Watch_Later_Saved,
	History,
	Check,
	Home,
	Playlists,
	Liked,
	Spinner,
	Hide,
}
ICON_FILES :: [Icon]string {
	.Play              = "play",
	.Pause             = "pause",
	.Slower            = "minus",
	.Faster            = "plus",
	.Account           = "user-round",
	.Search            = "search",
	.Subscriptions     = "gallery-vertical-end",
	.Watch_Later       = "clock",
	.Watch_Later_Saved = "clock-check",
	.History           = "rotate-ccw-clock",
	.Check             = "check",
	.Home              = "house",
	.Playlists         = "list-video",
	.Liked             = "thumbs-up",
	.Spinner           = "loader-circle",
	.Hide              = "eye-off",
}
icons: [Icon]^sdl.Texture
icon_pixels: c.int

// SDL textures scale linearly by default. Opaque covers still need blending
// for the rounded edge coverage.
upload_surface :: proc(renderer: ^sdl.Renderer, surface: ^sdl.Surface) -> ^sdl.Texture {
	texture := sdl.CreateTextureFromSurface(renderer, surface)
	if texture != nil && !sdl.SetTextureBlendMode(texture, sdl.BLENDMODE_BLEND) {
		sdl.DestroyTexture(texture)
		return nil
	}
	return texture
}

load_texture :: proc(renderer: ^sdl.Renderer, path: cstring) -> ^sdl.Texture {
	surface := img.Load(path)
	defer sdl.DestroySurface(surface)
	return surface == nil ? nil : upload_surface(renderer, surface)
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

// Icons are white. A tint borrows a static color, so it outlives the layout.
icon :: proc(id: Icon, size: f32 = 48, tint: ^clay.Color = nil) {
	if clay.UI()(
	{
		layout = {
			sizing = {
				width = clay.SizingFixed(scaled(size)),
				height = clay.SizingFixed(scaled(size)),
			},
		},
		image = {imageData = rawptr(icons[id])},
		userData = tint,
	},
	) {}
}
