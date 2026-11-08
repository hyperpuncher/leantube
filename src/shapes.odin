package main

import clay "../vendor/clay"
import "core:math"
import sdl "vendor:sdl3"

// Round clip bounds outward so fractional edges do not leave a one-pixel gap.
pixel_bounds :: proc(rect: sdl.FRect) -> sdl.Rect {
	x, y := i32(math.floor(rect.x)), i32(math.floor(rect.y))
	return {x, y, i32(math.ceil(rect.x + rect.w)) - x, i32(math.ceil(rect.y + rect.h)) - y}
}

// Draw only the bottom strip of the same rounded shape used for the cover.
rounded_progress :: proc(
	renderer: ^sdl.Renderer,
	rect: sdl.FRect,
	corners: clay.CornerRadius,
	percent: f32,
	clip: sdl.Rect,
) -> bool {
	saved_clip := clip
	defer _ = sdl.SetRenderClipRect(renderer, &saved_clip)
	strip := pixel_bounds({rect.x, rect.y + rect.h - scaled(4), rect.w, scaled(4)})
	completed := i32(f32(strip.w) * percent / 100)
	for color, i in ([2]clay.Color{COLOR_TRACK, COLOR_ACCENT}) {
		part := strip
		if i == 0 {
			part.x += completed
			part.w -= completed
		} else {part.w = completed}
		visible: sdl.Rect
		if !sdl.GetRectIntersection(clip, part, &visible) {continue}
		if !sdl.SetRenderClipRect(renderer, &visible) ||
		   !rounded_shape(renderer, rect, corners, color) {return false}
	}
	return true
}

// SDL geometry has no edge antialiasing. A one-pixel alpha fringe smooths
// rounded fills and images without masks, render targets, or another renderer.
// A wider fringe gives popup shadows the same fade without a blur texture.
rounded_shape :: proc(
	renderer: ^sdl.Renderer,
	rect: sdl.FRect,
	corners: clay.CornerRadius,
	color: clay.Color,
	texture: ^sdl.Texture = nil,
	uv: sdl.FRect = {0, 0, 1, 1},
	edge_width: f32 = 1,
) -> bool {
	if rect.w <= 0 || rect.h <= 0 {return true}
	SEGMENTS :: 12
	POINTS :: 4 * (SEGMENTS + 1)
	vertices: [POINTS * 2 + 1]sdl.Vertex
	indices: [POINTS * 9]i32
	tint := sdl.FColor{color[0] / 255, color[1] / 255, color[2] / 255, color[3] / 255}
	clear := tint
	clear.a = 0
	vertices[0] = {
		{rect.x + rect.w / 2, rect.y + rect.h / 2},
		tint,
		{uv.x + uv.w / 2, uv.y + uv.h / 2},
	}
	radii := [4]f32{corners.topLeft, corners.topRight, corners.bottomRight, corners.bottomLeft}
	for raw_radius, corner in radii {
		radius := clamp(raw_radius, 0, min(rect.w, rect.h) / 2)
		cx := corner == 0 || corner == 3 ? rect.x + radius : rect.x + rect.w - radius
		cy := corner < 2 ? rect.y + radius : rect.y + rect.h - radius
		for step in 0 ..= SEGMENTS {
			angle := (f32(corner + 2) + f32(step) / SEGMENTS) * math.PI / 2
			dx, dy := math.cos(angle), math.sin(angle)
			index := corner * (SEGMENTS + 1) + step
			for edge in 0 ..< 2 {
				r := max(0, radius + (edge == 0 ? -0.5 : 0.5) * edge_width)
				x, y := cx + dx * r, cy + dy * r
				vertices[1 + index + edge * POINTS] = {
					{x, y},
					edge == 0 ? tint : clear,
					{
						uv.x + clamp((x - rect.x) / rect.w, 0, 1) * uv.w,
						uv.y + clamp((y - rect.y) / rect.h, 0, 1) * uv.h,
					},
				}
			}
			a, b := i32(index + 1), i32((index + 1) % POINTS + 1)
			oa, ob := a + POINTS, b + POINTS
			triangles := [9]i32{0, a, b, a, oa, ob, a, ob, b}
			copy(indices[index * 9:][:9], triangles[:])
		}
	}
	return sdl.RenderGeometry(
		renderer,
		texture,
		raw_data(vertices[:]),
		len(vertices),
		raw_data(indices[:]),
		len(indices),
	)
}
