package main

import sdl "vendor:sdl3"

tv_cursor: ^sdl.Cursor

// Follow SDL-webOS: load the firmware arrow with hotspot (0, 0).
// This B9 uses the "small" pointer setting. SDL core provides the PNG loader.
open_tv_cursor :: proc() -> bool {
	surface := sdl.LoadPNG("/usr/share/im/cursorTypeAszSstN.png")
	if surface == nil {return false}
	defer sdl.DestroySurface(surface)
	// SDL3's linear-space premultiplication left 11 bottom-edge pixels with
	// RGB above alpha in the Wayland buffer. Bound the input once so the B9
	// blends them correctly. Keep opacity and the firmware file unchanged.
	for y in 0 ..< surface.h {
		for x in 0 ..< surface.w {
			r, g, b, a: u8
			if !sdl.ReadSurfacePixel(surface, x, y, &r, &g, &b, &a) {return false}
			if r > a || g > a || b > a {
				if !sdl.WriteSurfacePixel(surface, x, y, min(r, a), min(g, a), min(b, a), a) {
					return false
				}
			}
		}
	}
	tv_cursor = sdl.CreateColorCursor(surface, 0, 0)
	if tv_cursor == nil {return false}
	return sdl.SetCursor(tv_cursor)
}

close_tv_cursor :: proc() {
	if tv_cursor != nil {sdl.DestroyCursor(tv_cursor); tv_cursor = nil}
}
