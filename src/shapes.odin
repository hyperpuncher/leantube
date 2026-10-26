package main

import clay "../vendor/clay"
import "core:math"
import sdl "vendor:sdl3"

// SDL geometry has no edge antialiasing. A one-pixel alpha fringe smooths
// rounded fills and images without masks, render targets, or another renderer.
rounded_shape :: proc(
	renderer: ^sdl.Renderer,
	rect: sdl.FRect,
	corners: clay.CornerRadius,
	color: clay.Color,
	texture: ^sdl.Texture = nil,
) -> bool {
	if rect.w <= 0 || rect.h <= 0 {return true}
	SEGMENTS :: 12
	POINTS :: 4 * (SEGMENTS + 1)
	vertices: [POINTS * 2 + 1]sdl.Vertex
	indices: [POINTS * 9]i32
	tint := sdl.FColor{color[0] / 255, color[1] / 255, color[2] / 255, color[3] / 255}
	clear := tint
	clear.a = 0
	vertices[0] = {{rect.x + rect.w / 2, rect.y + rect.h / 2}, tint, {0.5, 0.5}}
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
				r := max(0, radius + (edge == 0 ? -0.5 : 0.5))
				x, y := cx + dx * r, cy + dy * r
				vertices[1 + index + edge * POINTS] = {
					{x, y},
					edge == 0 ? tint : clear,
					{clamp((x - rect.x) / rect.w, 0, 1), clamp((y - rect.y) / rect.h, 0, 1)},
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
