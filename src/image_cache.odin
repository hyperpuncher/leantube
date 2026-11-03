package main

import "./http"
import yt "./youtube"
import "core:c"
import "core:fmt"
import "core:hash"
import "core:os"
import "core:slice"
import "core:strings"
import sdl "vendor:sdl3"

// Used only by the network worker. Keep the original encoded image bytes.
IMAGE_CACHE_BYTES :: 256 * 1024 * 1024
Image_Cache :: struct {
	directory:     string,
	maximum_bytes: i64,
}

image_cache_path :: proc(cache: Image_Cache, source: string) -> string {
	if cache.directory == "" {return ""}
	return fmt.aprintf("%s/%016x.image", cache.directory, hash.fnv64a(transmute([]u8)source))
}

// Reserve space before writing. Hits do not change the download order.
trim_image_cache :: proc(cache: Image_Cache, incoming_bytes: i64 = 0) -> bool {
	if cache.directory == "" || incoming_bytes > cache.maximum_bytes {return false}
	// SDL uses libc filesystem APIs; Odin's directory scan requires statx.
	directory := strings.clone_to_cstring(cache.directory)
	defer delete(directory)
	count: c.int
	names := sdl.GlobDirectory(directory, "*.image", {}, &count)
	if names == nil {return false}
	defer sdl.free(names)
	Entry :: struct {
		path:     cstring,
		size:     i64,
		modified: sdl.Time,
	}
	files: [dynamic]Entry
	defer {for file in files {delete(file.path)}; delete(files)}
	total := incoming_bytes
	for i in 0 ..< count {
		path := fmt.caprintf("%s/%s", cache.directory, cstring(names[i]))
		info: sdl.PathInfo
		if !sdl.GetPathInfo(path, &info) {delete(path); return false}
		if info.type != .FILE {delete(path); continue}
		append(&files, Entry{path, i64(info.size), info.modify_time})
		total += i64(info.size)
	}
	if total <= cache.maximum_bytes {return true}
	slice.sort_by(files[:], proc(a, b: Entry) -> bool {return a.modified < b.modified})
	for file in files {
		if total <= cache.maximum_bytes {return true}
		if os.remove(string(file.path)) == nil {total -= file.size}
	}
	return total <= cache.maximum_bytes
}

// A scheduling hint only; reads still decode and reject corrupt cache files.
cached_image_exists :: proc(cache: Image_Cache, source: string) -> bool {
	path := image_cache_path(cache, source)
	defer delete(path)
	if path == "" {return false}
	cpath := strings.clone_to_cstring(path)
	defer delete(cpath)
	info: sdl.PathInfo
	return sdl.GetPathInfo(cpath, &info) && info.type == .FILE
}

// Return owned pixels without resolving or downloading the image source.
read_cached_image :: proc(cache: Image_Cache, source: string, target: i32) -> ^sdl.Surface {
	path := image_cache_path(cache, source)
	defer delete(path)
	if path == "" {return nil}
	bytes, error := os.read_entire_file(path, context.allocator)
	defer delete(bytes)
	surface: ^sdl.Surface
	if error == nil {surface = decode_image(bytes, target)}
	if surface == nil {_ = os.remove(path)}
	return surface
}

load_cached_image :: proc(
	cache: Image_Cache,
	client: ^http.Client,
	source: string,
	target: i32 = 0,
	fetch: type_of(yt.fetch_thumbnail) = yt.fetch_thumbnail,
	cache_source: string = "",
) -> ^sdl.Surface {
	if source == "" {return nil}
	// Channel IDs remain available after restart, before their avatar URL is known.
	key := cache_source != "" ? cache_source : source
	if surface := read_cached_image(cache, key, target); surface != nil {return surface}

	bytes: [dynamic]u8
	if strings.has_prefix(source, "https://") {
		response, error := fetch(client, source)
		if error == nil &&
		   response.status == 200 {bytes = response.body} else {delete(response.body)}
	} else {
		bytes = yt.thumbnail(client, source, network_stopping, fetch)
	}
	defer delete(bytes)
	surface := decode_image(bytes[:], target)
	if surface != nil && trim_image_cache(cache, i64(len(bytes))) {
		// Cache files are disposable: a partial file is fetched again on the next read.
		path := image_cache_path(cache, key)
		defer delete(path)
		if path != "" && os.write_entire_file(path, bytes[:]) != nil {_ = os.remove(path)}
	}
	return surface
}
