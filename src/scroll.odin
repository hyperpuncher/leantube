package main

import clay "../vendor/clay"

// Keep keyboard focus visible without changing wheel-driven scrolling.
reveal_selected_video :: proc() -> bool {
	scroll := clay.GetScrollContainerData(clay.ID("library-scroll"))
	viewport := clay.GetElementData(clay.ID("library-scroll"))
	item := clay.GetElementData(clay.ID("video", u32(selected)))
	if !scroll.found || !viewport.found || !item.found {return false}
	offset: f32
	if item.boundingBox.y < viewport.boundingBox.y {
		offset = viewport.boundingBox.y - item.boundingBox.y
	} else if bottom := item.boundingBox.y + item.boundingBox.height;
	   bottom > viewport.boundingBox.y + viewport.boundingBox.height {
		offset = viewport.boundingBox.y + viewport.boundingBox.height - bottom
	}
	scroll.scrollPosition^[1] += offset
	return offset != 0
}
