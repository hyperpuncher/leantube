package main

import clay "../vendor/clay"
import "./model"
import "core:fmt"
import "core:hash"
import "core:strings"
import sdl "vendor:sdl3"

// Retain visible feed images, not entire pages. SDL owns reference counting.
IMAGE_TEXTURE_BYTES :: 64 * 1024 * 1024
Image_Key :: struct {
	source: u64,
	target: i32,
}
Image_Texture :: struct {
	texture: ^sdl.Texture,
	bytes:   i64,
	used:    u64,
}
image_textures: map[Image_Key]Image_Texture
image_texture_bytes: i64
image_texture_tick: u64

image_key :: proc(source: string, target: i32) -> Image_Key {
	if source == "" {return {}}
	return {hash.fnv64a(transmute([]u8)source), target}
}

retain_image_texture :: proc(key: Image_Key, texture: ^sdl.Texture) {
	if key == {} || texture == nil {return}
	bytes := i64(texture.w) * i64(texture.h) * 4
	if bytes > IMAGE_TEXTURE_BYTES {return}
	if image_textures == nil {image_textures = make(map[Image_Key]Image_Texture)}
	if previous, found := image_textures[key]; found {
		if previous.texture == texture {
			image_texture_tick += 1
			previous.used = image_texture_tick
			image_textures[key] = previous
			return
		}
		image_texture_bytes -= previous.bytes
		sdl.DestroyTexture(previous.texture)
		delete_key(&image_textures, key)
	}
	for image_texture_bytes + bytes > IMAGE_TEXTURE_BYTES {
		oldest: Image_Key
		stamp := max(u64)
		for id, entry in image_textures {
			if entry.used < stamp {oldest, stamp = id, entry.used}
		}
		entry := image_textures[oldest]
		image_texture_bytes -= entry.bytes
		sdl.DestroyTexture(entry.texture)
		delete_key(&image_textures, oldest)
	}
	texture.refcount += 1
	image_texture_tick += 1
	image_textures[key] = {texture, bytes, image_texture_tick}
	image_texture_bytes += bytes
}

// Return an owned reference, released by the existing catalog cleanup.
take_image_texture :: proc(key: Image_Key) -> ^sdl.Texture {
	entry, found := image_textures[key]
	if !found {return nil}
	image_texture_tick += 1
	entry.used = image_texture_tick
	image_textures[key] = entry
	entry.texture.refcount += 1
	return entry.texture
}

close_image_textures :: proc() {
	for _, entry in image_textures {sdl.DestroyTexture(entry.texture)}
	delete(image_textures)
	image_textures = nil
	image_texture_bytes, image_texture_tick = 0, 0
}

card_image_source :: proc(video: model.Video, avatar: bool) -> string {
	if avatar {return video.avatar_url != "" ? video.avatar_url : model.video_channel_id(video)}
	return video.thumbnail_url != "" ? video.thumbnail_url : video.id
}

preserve_catalog_images :: proc() {
	if clay.GetCurrentContext() == nil {return}
	viewport := clay.GetElementData(clay.ID("library-scroll"))
	if !viewport.found {return}
	clip := pixel_bounds(
		{
			viewport.boundingBox.x,
			viewport.boundingBox.y,
			viewport.boundingBox.width,
			viewport.boundingBox.height,
		},
	)
	for video, i in catalog.videos {
		card := clay.GetElementData(clay.ID("video", u32(i)))
		box := card.boundingBox
		visible: sdl.Rect
		if !card.found ||
		   !sdl.GetRectIntersection(
				   pixel_bounds({box.x, box.y, box.width, box.height}),
				   clip,
				   &visible,
			   ) {continue}
		index := video.cover_index
		if index >= 0 && index < len(textures) {
			retain_image_texture(image_key(card_image_source(video, false), 0), textures[index])
		}
		if index >= 0 && index < len(card_avatars) {
			retain_image_texture(
				image_key(card_image_source(video, true), 2 * CARD_AVATAR_SIZE),
				card_avatars[index],
			)
		}
	}
	retain_image_texture(
		image_key(catalog.channel.avatar_url, 2 * CHANNEL_AVATAR_SIZE),
		channel_avatar,
	)
}

append_image_request :: proc(
	jobs: ^[dynamic]Image_Request,
	source: string,
	slot: ^^sdl.Texture,
	index: int,
	target: i32,
) -> bool {
	if source == "" || slot^ != nil {return false}
	slot^ = take_image_texture(image_key(source, target))
	if slot^ != nil {return true}
	append(
		jobs,
		Image_Request{source = strings.clone(source), index = index, target = target, page = page},
	)
	return false
}

// Restore all hits before the next frame. Only misses go to the worker.
queue_catalog_images :: proc() {
	jobs: [dynamic]Image_Request
	restored := int(
		append_image_request(
			&jobs,
			catalog.channel.avatar_url,
			&channel_avatar,
			-1,
			2 * CHANNEL_AVATAR_SIZE,
		),
	)
	batch_size := max(1, grid_columns) * 2
	for first := 0; first < len(catalog.videos); first += batch_size {
		batch := catalog.videos[first:min(first + batch_size, len(catalog.videos))]
		for avatar in ([2]bool{false, true}) {
			for video in batch {
				index := video.cover_index
				slot := avatar ? &card_avatars[index] : &textures[index]
				restored += int(
					append_image_request(
						&jobs,
						card_image_source(video, avatar),
						slot,
						index,
						avatar ? 2 * CARD_AVATAR_SIZE : 0,
					),
				)
			}
		}
	}
	fmt.printf("images restored=%d queued=%d\n", restored, len(jobs))
	if len(jobs) >
	   0 {_ = submit_network({kind = .Images, page = page, images = jobs})} else {delete(jobs)}
}
