package main

import ttf "vendor:sdl3/ttf"

// Card geometry is known before layout, so offscreen rows can be omitted.
Grid_Metrics :: struct {
	card_width, text_width: f32,
	padding, cover, gap:    f32,
	card_gap, text_gap:     f32,
	line, channel, meta:    f32,
	leading:                f32,
}

grid_metrics :: proc() -> Grid_Metrics {
	// Rounded like the Clay config values so measured and drawn sizes agree.
	gap := f32(spacing(16))
	padding := f32(spacing(12))
	content := view_width - scaled(128) - scaled(32) - scaled(48)
	card_width := max(0, (content - gap * f32(grid_columns - 1)) / f32(grid_columns))
	return {
		card_width = card_width,
		text_width = card_width - padding * 2,
		padding    = padding,
		cover      = (card_width - padding * 2) * 9 / 16,
		gap        = gap,
		card_gap   = f32(spacing(8)),
		text_gap   = f32(spacing(2)),
		line       = f32(ttf.GetFontHeight(fonts[.Small])),
		channel    = max(f32(ttf.GetFontHeight(fonts[.Caption])), scaled(CARD_AVATAR_SIZE + 8)),
		meta       = f32(ttf.GetFontHeight(fonts[.Caption])),
		// Scrolls away, but leaves the same first-row inset as the old padding.
		leading    = f32(spacing(32)),
	}
}

// A card grows only for what it draws: title lines, channel row and meta text.
card_height :: proc(metrics: Grid_Metrics, shape: Card_Shape) -> f32 {
	height :=
		metrics.padding * 2 +
		metrics.cover +
		metrics.card_gap +
		f32(shape.lines) * metrics.line +
		metrics.text_gap +
		(shape.channel ? metrics.channel : metrics.meta)
	if shape.meta {height += metrics.text_gap + metrics.meta}
	return height
}

grid_rows :: proc(count, columns: int) -> int {return (count + columns - 1) / max(columns, 1)}
