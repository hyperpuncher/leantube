package main

import "./model"
import sdl "vendor:sdl3"

Request_Kind :: enum uintptr {
	Register,
	Load,
	Subscribe,
	Foreground,
	Control,
	Seek,
	Unload,
}
running := true
paused: bool
loaded: bool
timeline := model.Timeline {
	seek_target_ms = -1,
}
duration_ms: f64
rate: f64 = 1
dirty := true
browsing := true
return_to_grid: bool
selected: int
catalog: model.Catalog
textures: [model.MAX_VIDEOS]^sdl.Texture
app_directory: string
notice: string
