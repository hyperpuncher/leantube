package main

import clay "../vendor/clay"
import "./model"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:math"
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

loading_active :: proc() -> bool {
	if login_screen {return login_waiting || login_next_poll > 0}
	return browsing ? (search_loading && len(catalog.videos) == 0) || card_menu_waiting : !loaded
}

// Preview screenshots can use white, so a fade has no dark video behind it.
WHITE_PREVIEW :: #config(UI_WHITE, false)

set_color :: proc(renderer: ^sdl.Renderer, color: clay.Color) -> bool {
	return sdl.SetRenderDrawColor(renderer, u8(color[0]), u8(color[1]), u8(color[2]), u8(color[3]))
}

// Render the fade at screen resolution. Subpixel alpha dithering must not
// be stretched into visible stripes.
PLAYER_FADE_ALPHA :: 216 // 85% opacity in SDL's 8-bit alpha.
fade_textures: [2]^sdl.Texture
fade_heights: [2]i32

bayer_value :: proc(x, y: int) -> u8 {
	quad := [4]u8{0, 2, 3, 1}
	value: u8
	for bit in u32(0) ..< 3 {
		quadrant := ((x >> bit) & 1) | (((y >> bit) & 1) << 1)
		value = value * 4 + quad[quadrant]
	}
	return value
}

// Rebuild only when the layout size changes.
open_fade :: proc(renderer: ^sdl.Renderer, slot: int, height: f32) -> bool {
	rows := max(2, i32(math.round(height)))
	if fade_textures[slot] != nil && fade_heights[slot] == rows {return true}
	if fade_textures[slot] != nil {
		sdl.DestroyTexture(fade_textures[slot])
		fade_textures[slot] = nil
	}
	// Tile the eight-pixel dither period, never stretch it horizontally.
	columns :: 8
	pixels := make([]u8, columns * int(rows) * 4)
	defer delete(pixels)
	for y in 0 ..< int(rows) {
		// Bake the header flip so SDL can tile both fades directly.
		source_y := slot == 1 ? int(rows) - 1 - y : y
		// Smoothstep with less than one alpha level of ordered dither.
		t := f32(source_y) / f32(rows - 1)
		alpha := t * t * (3 - 2 * t) * 255
		for x in 0 ..< columns {
			threshold := (f32(bayer_value(x, source_y)) + 0.5) / 64
			base := (y * columns + x) * 4
			pixels[base + 3] = u8(clamp(alpha + threshold, 0, 255))
		}
	}
	texture := sdl.CreateTexture(renderer, .RGBA32, .STATIC, columns, rows)
	if texture == nil {return false}
	if !sdl.UpdateTexture(texture, nil, raw_data(pixels), columns * 4) ||
	   !sdl.SetTextureBlendMode(texture, sdl.BLENDMODE_BLEND) ||
	   !sdl.SetTextureAlphaMod(texture, PLAYER_FADE_ALPHA) ||
	   !sdl.SetTextureScaleMode(texture, .NEAREST) {
		sdl.DestroyTexture(texture)
		return false
	}
	fade_textures[slot], fade_heights[slot] = texture, rows
	return true
}

close_fade :: proc() {
	for &texture in fade_textures {
		if texture != nil {sdl.DestroyTexture(texture); texture = nil}
	}
}

// Fade from clear to 85% black. Extend beyond the controls without moving
// them, and flip the same curve to darken the header at the top.
player_fade :: proc(renderer: ^sdl.Renderer, id: string, flip: bool, extend: f32) -> bool {
	box := clay.GetElementData(clay.ID(id)).boundingBox
	if !flip {box.y -= extend}
	box.height += extend
	if !open_fade(renderer, int(flip), box.height) {return false}
	texture := fade_textures[int(flip)]
	rect := sdl.FRect{box.x, box.y, box.width, box.height}
	return sdl.RenderTextureTiled(renderer, texture, nil, 1, &rect)
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
	when WHITE_PREVIEW {
		if !browsing {color = {255, 255, 255, 255}}
	}
	if !set_color(renderer, color) || !sdl.RenderClear(renderer) {return false}
	// Clay borrows these strings until the render commands have been drawn.
	elapsed, total, speed, quality: string
	// quality is a static label and must not be freed.
	defer {delete(elapsed); delete(total); delete(speed)}
	// Each scroll update must have a layout. Idle updates without layouts
	// make Clay discard the container and its saved scroll position.
	if browsing {clay.UpdateScrollContainers(false, {0, wheel}, dt)}
	controls_visible := !browsing && player_controls_visible()
	clay.BeginLayout()
	if browsing {
		grid_layout()
	} else if controls_visible {
		elapsed = model.time_label(model.display_position(timeline))
		total = model.time_label(duration_ms, "--:--")
		quality = model.quality_label(stream_width, stream_height)
		speed = fmt.aprintf("%gx", rate)
		player_layout(elapsed, total, speed, quality)
	}
	commands := clay.EndLayout(0)
	if controls_visible &&
	   (!player_fade(renderer, "player-header", true, scaled(32)) ||
			   !player_fade(renderer, "controls", false, scaled(80))) {return false}
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
	// Keep two screens in reserve for both remote and wheel scrolling.
	if browsing && notice == "" {
		scroll := clay.GetScrollContainerData(clay.ID("library-scroll"))
		if scroll.found &&
		   scroll.contentDimensions.height + scroll.scrollPosition^[1] <=
			   scroll.scrollContainerDimensions.height * 3 {
			load_more()
		}
	}
	ok := render_commands(renderer, commands)
	if ok && browsing {preserve_catalog_images()}
	return ok
}

render_commands :: proc(
	renderer: ^sdl.Renderer,
	input: clay.ClayArray(clay.RenderCommand),
) -> bool {
	commands := input
	used_texts: int
	defer {
		for value in rendered_text[used_texts:] {ttf.DestroyText(value)}
		resize(&rendered_text, used_texts)
	}
	clips := make([dynamic]sdl.Rect)
	defer {delete(clips); _ = sdl.SetRenderClipRect(renderer, nil)}
	append(&clips, sdl.Rect{0, 0, i32(view_width), i32(view_height)})
	for i in 0 ..< commands.length {
		command := clay.RenderCommandArray_Get(&commands, i)
		box := command.boundingBox
		rect := sdl.FRect{box.x, box.y, box.width, box.height}
		if command.commandType == .Rectangle ||
		   command.commandType == .Image ||
		   command.commandType == .Custom ||
		   command.commandType == .Text {
			visible: sdl.Rect
			if !sdl.GetRectIntersection(
				pixel_bounds(rect),
				clips[len(clips) - 1],
				&visible,
			) {continue}
		}
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
			if texture == icons[.Spinner] {
				if !sdl.RenderTextureRotated(
					renderer,
					texture,
					nil,
					&rect,
					f64(sdl.GetTicks() % 1000) * 0.36,
					nil,
					.NONE,
				) {return false}
				continue
			}
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
		case .Custom:
			data := command.renderData.custom
			percent := (cast(^f32)data.customData)^
			if !rounded_progress(
				renderer,
				rect,
				data.cornerRadius,
				percent,
				clips[len(clips) - 1],
			) {
				return false
			}
		case .Text:
			text := command.renderData.text
			if text.stringContents.length == 0 {continue}
			clip := clips[len(clips) - 1]
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
			value := frame_text(used_texts, font, display)
			if value == nil {return false}
			used_texts += 1
			ok :=
				ttf.SetTextColor(value, u8(color[0]), u8(color[1]), u8(color[2]), u8(color[3])) &&
				ttf.DrawRendererText(value, math.round(box.x), math.round(box.y))
			if !ok {return false}
		case .ScissorStart:
			parent := clips[len(clips) - 1]
			next := pixel_bounds(rect)
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
