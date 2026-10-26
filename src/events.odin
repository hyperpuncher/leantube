package main

import sdl "vendor:sdl3"

handle_event :: proc(renderer: ^sdl.Renderer, event: sdl.Event) -> (wheel: f32) {
	#partial switch event.type {
	case .QUIT:
		running = false
	case .WINDOW_EXPOSED, .WINDOW_PIXEL_SIZE_CHANGED:
		dirty = true
	case .KEY_DOWN:
		key(input_key(event.key.raw, event.key.key), sdl.GetRenderWindow(renderer))
	case .TEXT_INPUT:
		if browsing {append_search_text(string(event.text.text))}
	case .MOUSE_WHEEL:
		if browsing {
			controls_pointer(renderer, event.wheel.mouse_x, event.wheel.mouse_y, false, false)
			wheel = event.wheel.y
			if event.wheel.direction == .FLIPPED {wheel = -wheel}
		}
	case .MOUSE_MOTION:
		controls_pointer(
			renderer,
			event.motion.x,
			event.motion.y,
			.LEFT in event.motion.state,
			false,
		)
	case .MOUSE_BUTTON_DOWN:
		if event.button.button == sdl.BUTTON_LEFT {
			controls_pointer(renderer, event.button.x, event.button.y, true, true)
		}
	case .MOUSE_BUTTON_UP:
		if event.button.button == sdl.BUTTON_LEFT {
			controls_pointer(renderer, event.button.x, event.button.y, false, false)
		}
	}
	return
}
