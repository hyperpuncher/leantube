package main

import clay "../vendor/clay"
import sdl "vendor:sdl3"

TOAST_MS :: 3000
toast_until: u64

// Keep the error state after the notification leaves the screen.
show_notice :: proc(message: string) {
	notice = message
	toast_until = sdl.GetTicks() + TOAST_MS
	dirty = true
}

expire_toast :: proc(now: u64) {
	if toast_until == 0 || now < toast_until {return}
	toast_until = 0
	dirty = true
}

toast_layout :: proc() {
	if notice == "" || toast_until == 0 {return}
	if clay.UI(clay.ID("toast"))(
	{
		layout = {
			sizing = {width = clay.SizingFit({max = min(scaled(720), view_width - scaled(64))})},
			padding = padding(24, 24, 16, 16),
		},
		userData = &POPUP_SHADOW,
		backgroundColor = COLOR_TEXT,
		cornerRadius = clay.CornerRadiusAll(scaled(12)),
		floating = {
			attachTo = .Root,
			attachment = {element = .RightBottom, parent = .RightBottom},
			offset = {-scaled(32), -scaled(32)},
			zIndex = 20,
			pointerCaptureMode = .Passthrough,
		},
	},
	) {
		label(notice, .Small, COLOR_BACKGROUND, .Words)
	}
}
