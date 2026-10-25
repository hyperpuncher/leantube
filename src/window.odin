package main

import sdl "vendor:sdl3"

create_window :: proc() -> ^sdl.Window {
	_ = sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(sdl.GL_CONTEXT_PROFILE_ES))
	_ = sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 2)
	_ = sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 0)
	_ = sdl.GL_SetAttribute(.ALPHA_SIZE, 8)
	properties := sdl.CreateProperties()
	defer sdl.DestroyProperties(properties)
	_ = sdl.SetBooleanProperty(
		properties,
		sdl.PROP_WINDOW_CREATE_WAYLAND_SURFACE_ROLE_CUSTOM_BOOLEAN,
		true,
	)
	_ = sdl.SetBooleanProperty(properties, sdl.PROP_WINDOW_CREATE_OPENGL_BOOLEAN, true)
	_ = sdl.SetBooleanProperty(properties, sdl.PROP_WINDOW_CREATE_TRANSPARENT_BOOLEAN, true)
	_ = sdl.SetNumberProperty(properties, sdl.PROP_WINDOW_CREATE_WIDTH_NUMBER, 1920)
	_ = sdl.SetNumberProperty(properties, sdl.PROP_WINDOW_CREATE_HEIGHT_NUMBER, 1080)
	return sdl.CreateWindowWithProperties(properties)
}
