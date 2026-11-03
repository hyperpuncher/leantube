package main

import clay "../vendor/clay"

// Rows are virtualized, so reveal from row geometry instead of element bounds.
reveal_selected_video :: proc() -> bool {
	scroll := clay.GetScrollContainerData(clay.ID("library-scroll"))
	if !scroll.found || scroll.scrollPosition == nil {return false}
	row := selected / grid_columns
	if row >= len(row_heights) {return false}
	top := row_offsets[row]
	bottom := top + row_heights[row]
	position := scroll.scrollPosition^[1]
	height := scroll.scrollContainerDimensions.height
	if top < -position {
		position = -top
	} else if bottom > -position + height {
		position = -(bottom - height)
	}
	content := scroll.contentDimensions.height
	position = content > height ? clamp(position, height - content, 0) : 0
	if position == scroll.scrollPosition^[1] {return false}
	scroll.scrollPosition^[1] = position
	return true
}

reveal_scroll_item :: proc(scroll_id, item_id: clay.ElementId) -> bool {
	scroll := clay.GetScrollContainerData(scroll_id)
	viewport := clay.GetElementData(scroll_id)
	item := clay.GetElementData(item_id)
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
