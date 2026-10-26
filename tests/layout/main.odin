package main

import clay "../../vendor/clay"
import "base:runtime"
import "core:fmt"

when ODIN_ARCH == .arm32 {
	foreign import native "system:clay"
	foreign native {
		tv_clay_abi :: proc(command_size, config_size, error_size: u32) -> bool ---
	}
}

layout_error :: proc "c" (error: clay.ErrorData) {
	context = runtime.default_context()
	fmt.eprintln("Clay error:", string(error.errorText.chars[:error.errorText.length]))
	assert(false, "layout failed")
}

main :: proc() {
	when ODIN_ARCH == .arm32 {
		assert(
			tv_clay_abi(
				u32(size_of(clay.RenderCommand)),
				u32(size_of(clay.ElementDeclaration)),
				u32(size_of(clay.ErrorData)),
			),
		)
	}
	clay.SetMaxElementCount(128)
	clay.SetMaxMeasureTextCacheWordCount(512)
	memory := make([]u8, int(clay.MinMemorySize()))
	defer delete(memory)
	clay.Initialize(
		clay.CreateArenaWithCapacityAndMemory(uint(len(memory)), raw_data(memory)),
		{960, 540},
		{handler = layout_error},
	)
	clay.BeginLayout()
	if clay.UI(clay.ID("root"))(
	{
		layout = {
			sizing = {width = clay.SizingFixed(960), height = clay.SizingFixed(540)},
			layoutDirection = .TopToBottom,
		},
	},
	) {
		if clay.UI()({layout = {sizing = {height = clay.SizingGrow({})}}}) {}
		if clay.UI(clay.ID("panel"))(
		{
			layout = {sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(80)}},
			backgroundColor = {10, 20, 30, 255},
		},
		) {}
	}
	_ = clay.EndLayout(0)
	panel := clay.GetElementData(clay.ID("panel"))
	assert(
		panel.found &&
		panel.boundingBox.x == 0 &&
		panel.boundingBox.y == 460 &&
		panel.boundingBox.width == 960 &&
		panel.boundingBox.height == 80,
	)
	fmt.println("bottom panel layout passed")
	// Image data is opaque to Clay. Verify that the C/Odin boundary preserves
	// the renderer's pointer and the dimensions used for a thumbnail.
	marker: u8
	clay.BeginLayout()
	if clay.UI(clay.ID("thumbnail"))(
	{
		layout = {sizing = {width = clay.SizingFixed(256), height = clay.SizingFixed(144)}},
		image = {imageData = rawptr(&marker)},
	},
	) {}
	commands := clay.EndLayout(0)
	found := false
	for i in 0 ..< commands.length {
		command := clay.RenderCommandArray_Get(&commands, i)
		if command.commandType == .Image {
			assert(command.renderData.image.imageData == rawptr(&marker))
			assert(command.boundingBox.width == 256 && command.boundingBox.height == 144)
			found = true
		}
	}
	assert(found, "thumbnail image command missing")
	fmt.println("thumbnail image layout passed")
}
