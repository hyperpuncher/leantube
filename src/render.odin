package main

import clay "../vendor/clay"
import "./model"
import "base:runtime"
import "core:c"
import "core:fmt"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

clay_error :: proc "c" (error: clay.ErrorData) {
	context = runtime.default_context()
	fmt.eprintln("layout error:", string(error.errorText.chars[:error.errorText.length]))
	running = false
}
measure_text :: proc "c" (
	text: clay.StringSlice,
	config: ^clay.TextElementConfig,
	data: rawptr,
) -> clay.Dimensions {
	font := fonts[Text_Style(config.fontId)]
	if text.length == 0 {return {0, f32(ttf.GetFontHeight(font))}}
	width, height: c.int
	if !ttf.GetStringSize(
		font,
		text.chars,
		c.size_t(text.length),
		&width,
		&height,
	) {running = false; return {}}
	return {f32(width), f32(height)}
}
label :: proc(
	text: string,
	style: Text_Style = .Body,
	color: clay.Color = COLOR_TEXT,
	wrap: clay.TextWrapMode = .None,
) {
	clay.Text(
		text,
		{fontId = u16(style), fontSize = text_sizes[style], textColor = color, wrapMode = wrap},
	)
}

set_color :: proc(renderer: ^sdl.Renderer, color: clay.Color) -> bool {
	return sdl.SetRenderDrawColor(renderer, u8(color[0]), u8(color[1]), u8(color[2]), u8(color[3]))
}

render :: proc(renderer: ^sdl.Renderer, wheel: f32 = 0, dt: f32 = 1.0 / 60) -> bool {
	if !refresh_view(renderer) {return false}
	if login_screen {
		if login_code != "" {_ = ensure_login_qr(renderer)}
		if !set_color(renderer, COLOR_BACKGROUND) || !sdl.RenderClear(renderer) {return false}
		clay.BeginLayout()
		login_layout()
		commands := clay.EndLayout(0)
		return render_commands(renderer, commands)
	}
	color: clay.Color
	if browsing {color = COLOR_BACKGROUND}
	if !set_color(renderer, color) || !sdl.RenderClear(renderer) {return false}
	// Clay borrows these strings until the render commands have been drawn.
	elapsed, total, speed, quality: string
	// quality is a static label and must not be freed.
	defer {delete(elapsed); delete(total); delete(speed)}
	// Each scroll update must have a layout. Idle updates without layouts
	// make Clay discard the container and its saved scroll position.
	if browsing {clay.UpdateScrollContainers(false, {0, wheel}, dt)}
	clay.BeginLayout()
	if browsing {
		grid_layout()
	} else if player_controls_visible() {
		elapsed = model.time_label(model.display_position(timeline))
		total = model.time_label(duration_ms, "--:--")
		quality = model.quality_label(stream_width, stream_height)
		speed = fmt.aprintf("%gx", rate)
		player_layout(elapsed, total, speed, quality)
	}
	commands := clay.EndLayout(0)
	if browsing && library_focus_pending {
		library_focus_pending = false
		if reveal_selected_video() {
			clay.BeginLayout()
			grid_layout()
			commands = clay.EndLayout(0)
		}
	}
	if browsing &&
	   card_menu &&
	   reveal_scroll_item(
		   clay.ID("card-menu-scroll"),
		   clay.ID("card-action", u32(card_menu_selected)),
	   ) {
		clay.BeginLayout()
		grid_layout()
		commands = clay.EndLayout(0)
	}
	// Cards are not clipped, so their captions are fitted to the measured width.
	if browsing && grid_measure_labels() {
		clay.BeginLayout()
		grid_layout()
		commands = clay.EndLayout(0)
	}
	return render_commands(renderer, commands)
}

render_commands :: proc(
	renderer: ^sdl.Renderer,
	input: clay.ClayArray(clay.RenderCommand),
) -> bool {
	commands := input
	clips := make([dynamic]sdl.Rect)
	defer {delete(clips); _ = sdl.SetRenderClipRect(renderer, nil)}
	append(&clips, sdl.Rect{0, 0, i32(view_width), i32(view_height)})
	for i in 0 ..< commands.length {
		command := clay.RenderCommandArray_Get(&commands, i)
		box := command.boundingBox
		rect := sdl.FRect{box.x, box.y, box.width, box.height}
		#partial switch command.commandType {
		case .Rectangle:
			data := command.renderData.rectangle
			if data.cornerRadius != (clay.CornerRadius{}) {
				if !rounded_shape(
					renderer,
					rect,
					data.cornerRadius,
					data.backgroundColor,
				) {return false}
			} else {
				if !set_color(renderer, data.backgroundColor) ||
				   !sdl.RenderFillRect(renderer, &rect) {return false}
			}
		case .Image:
			data := command.renderData.image
			texture := cast(^sdl.Texture)data.imageData
			if texture == nil {
				if !rounded_shape(renderer, rect, data.cornerRadius, COLOR_SURFACE) {return false}
				continue
			}
			if rect.w <= 0 || rect.h <= 0 {continue}
			width, height: f32
			if !sdl.GetTextureSize(texture, &width, &height) {return false}
			// Fill the destination without stretching. Crop only during drawing;
			// the original texture and downloaded file remain unchanged.
			scale := max(rect.w / width, rect.h / height)
			source := sdl.FRect{0, 0, rect.w / scale, rect.h / scale}
			source.x = (width - source.w) / 2
			source.y = (height - source.h) / 2
			if data.cornerRadius != (clay.CornerRadius{}) {
				if !rounded_shape(
					renderer,
					rect,
					data.cornerRadius,
					{255, 255, 255, 255},
					texture,
					{source.x / width, source.y / height, source.w / width, source.h / height},
				) {return false}
			} else if !sdl.RenderTexture(renderer, texture, &source, &rect) {return false}
		case .Text:
			text := command.renderData.text
			if text.stringContents.length == 0 {continue}
			clip := clips[len(clips) - 1]
			if box.y >= f32(clip.y + clip.h) || box.y + box.height <= f32(clip.y) {continue}
			continued := false
			if i + 1 < commands.length {
				next := clay.RenderCommandArray_Get(&commands, i + 1)
				continued =
					next.commandType == .Text &&
					next.renderData.text.stringContents.baseChars ==
						text.stringContents.baseChars &&
					next.boundingBox.y >= f32(clip.y + clip.h)
			}
			font := fonts[Text_Style(text.fontId)]
			available := f32(clip.x + clip.w) - box.x
			display, owned := fit_text(
				font,
				string(text.stringContents.chars[:text.stringContents.length]),
				c.int(max(0, available)),
				continued,
			)
			defer if owned {delete(display)}
			if display == "" {continue}
			color := text.textColor
			value := ttf.CreateText(text_engine, font, raw_data(display), c.size_t(len(display)))
			if value == nil {return false}
			ok :=
				ttf.SetTextColor(value, u8(color[0]), u8(color[1]), u8(color[2]), u8(color[3])) &&
				ttf.DrawRendererText(value, box.x, box.y)
			ttf.DestroyText(value)
			if !ok {return false}
		case .ScissorStart:
			parent := clips[len(clips) - 1]
			next := sdl.Rect{i32(box.x), i32(box.y), i32(box.width), i32(box.height)}
			if !command.renderData.clip.horizontal {next.x = parent.x; next.w = parent.w}
			if !command.renderData.clip.vertical {next.y = parent.y; next.h = parent.h}
			clipped: sdl.Rect
			if !sdl.GetRectIntersection(parent, next, &clipped) {clipped = {}}
			append(&clips, clipped)
			if !sdl.SetRenderClipRect(renderer, &clipped) {return false}
		case .ScissorEnd:
			resize(&clips, len(clips) - 1)
			if !sdl.SetRenderClipRect(renderer, &clips[len(clips) - 1]) {return false}
		}
	}
	return sdl.RenderPresent(renderer)
}
