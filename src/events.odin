package main

import sdl "vendor:sdl3"

handle_event :: proc(renderer: ^sdl.Renderer, event: sdl.Event) -> (wheel: f32) {
	#partial switch event.type {
	case .QUIT:
		running = false
	case .WINDOW_EXPOSED, .WINDOW_PIXEL_SIZE_CHANGED:
		dirty = true
	case .WINDOW_FOCUS_LOST:
		card_press.active = false
	case .KEY_DOWN:
		code := input_key(event.key.raw, event.key.key)
		ok := code == sdl.K_RETURN || code == sdl.K_KP_ENTER || code == sdl.K_SPACE
		if ok && event.key.repeat {return}
		if ok && can_press_card() {
			if !card_press.active {begin_card_press(false, sdl.GetTicks())}
		} else {
			card_press.active = false
			key(code, sdl.GetRenderWindow(renderer))
		}
	case .KEY_UP:
		code := input_key(event.key.raw, event.key.key)
		if code == sdl.K_RETURN || code == sdl.K_KP_ENTER || code == sdl.K_SPACE {
			finish_card_press(false, sdl.GetTicks())
		}
	case .TEXT_INPUT:
		if browsing {append_search_text(string(event.text.text))}
	case .MOUSE_WHEEL:
		card_press.active = false
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
			finish_card_press(true, sdl.GetTicks())
		}
	}
	return
}
