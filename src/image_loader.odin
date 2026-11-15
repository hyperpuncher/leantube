#+build !wasi
package main

import "./http"
import yt "./youtube"
import "core:fmt"
import "core:strings"
import "core:sync"
import "core:thread"
import sdl "vendor:sdl3"

// Image downloads run beside the main network worker, so a slow API request
// or one slow image does not hold back the covers on screen. On the B9, four
// workers filled fast-scrolled rows about 6 times sooner than one, for about
// 30 MB more memory. Six were faster again, with slower frames during uploads.
IMAGE_WORKERS :: 4

Image_Loader :: struct {
	mutex:     sync.Mutex,
	changed:   sync.Cond,
	pending:   [dynamic]Image_Request,
	// Card indexes on screen, written by the UI thread after each layout.
	visible:   [2]int,
	cache:     Image_Cache,
	// Channel ID to avatar URL, filled by workers and the main network worker.
	avatars:   map[string]string,
	visitor:   string,
	stopping:  bool,
	threads:   [IMAGE_WORKERS]^thread.Thread,
	directory: string,
}
image_loader: Image_Loader

start_image_loader :: proc() -> bool {
	directory := auth_directory != "" ? auth_directory : app_directory
	image_loader.directory = fmt.aprintf("%s/.cache/images", directory)
	image_loader.cache = {
		directory     = image_loader.directory,
		maximum_bytes = IMAGE_CACHE_BYTES,
	}
	path := strings.clone_to_cstring(image_loader.directory)
	defer delete(path)
	if !sdl.CreateDirectory(path) || !trim_image_cache(image_loader.cache) {
		fmt.eprintln("image cache is unavailable")
	}
	for &worker in image_loader.threads {
		worker = thread.create(image_worker)
		if worker == nil {return false}
		thread.start(worker)
	}
	return true
}

stop_image_loader :: proc() {
	{
		sync.guard(&image_loader.mutex)
		image_loader.stopping = true
		sync.cond_broadcast(&image_loader.changed)
	}
	for &worker in image_loader.threads {
		if worker != nil {thread.destroy(worker); worker = nil}
	}
	clear_image_requests()
	delete(image_loader.pending)
	for id, url in image_loader.avatars {delete(id); delete(url)}
	delete(image_loader.avatars)
	delete(image_loader.visitor)
	delete(image_loader.directory)
	image_loader = {}
}

clear_image_requests :: proc() {
	for request in image_loader.pending {delete(request.source)}
	clear(&image_loader.pending)
}

// A new feed replaces waiting work. Requests already downloading finish and
// are dropped by their page number.
queue_images :: proc(requests: []Image_Request, replace: bool) {
	// Serve disk hits before downloads and URL lookups.
	for &request in requests {request.cached = cached_image_exists(image_loader.cache, request.source)}
	sync.guard(&image_loader.mutex)
	if replace {clear_image_requests()}
	append(&image_loader.pending, ..requests)
	sync.cond_broadcast(&image_loader.changed)
}

set_visible_images :: proc(first, last: int) {
	sync.guard(&image_loader.mutex)
	image_loader.visible = {first, last}
}

set_image_visitor :: proc(visitor: string) {
	sync.guard(&image_loader.mutex)
	if visitor == image_loader.visitor {return}
	delete(image_loader.visitor)
	image_loader.visitor = strings.clone(visitor)
}

// Channel and player avatars have no card and go first. Then choose disk
// hits, then the card nearest the screen, then covers before avatars.
@(private = "file")
image_priority :: proc(request: Image_Request, visible: [2]int) -> int {
	if request.index < 0 {return -1}
	distance := 0
	if request.index < visible[0] {distance = visible[0] - request.index}
	if request.index >= visible[1] {distance = request.index - visible[1] + 1}
	return (int(!request.cached) * 1_000_000 + distance) * 2 + int(request.target > 0)
}

@(private = "file")
take_image_request :: proc() -> (request: Image_Request, visitor: string, ok: bool) {
	sync.guard(&image_loader.mutex)
	for len(image_loader.pending) == 0 && !image_loader.stopping {
		sync.cond_wait(&image_loader.changed, &image_loader.mutex)
	}
	if image_loader.stopping {return}
	best := 0
	for candidate, i in image_loader.pending {
		if image_priority(candidate, image_loader.visible) <
		   image_priority(image_loader.pending[best], image_loader.visible) {best = i}
	}
	request = image_loader.pending[best]
	unordered_remove(&image_loader.pending, best)
	return request, strings.clone(image_loader.visitor), true
}

@(private = "file")
image_stopping :: proc() -> bool {
	sync.guard(&image_loader.mutex)
	return image_loader.stopping
}

@(private = "file")
image_worker :: proc(_: ^thread.Thread) {
	client, error := http.open()
	if error != nil {fmt.eprintln("image worker: HTTP client failed:", error); return}
	defer http.close(&client)
	for {
		request, visitor, ok := take_image_request()
		if !ok {return}
		defer {delete(request.source); delete(visitor)}
		surface := load_image_request(&client, request, visitor)
		if surface == nil {continue}
		if !post_network_result(
			   {
				   kind = request.target > 0 ? .Channel_Avatar : .Cover,
				   page = request.page,
				   index = request.index,
				   playback = request.playback,
				   surface = surface,
			   },
		   ) &&
		   image_stopping() {return}
	}
}

// Channel avatars may need one API lookup before the image download. Cache
// files use the channel ID, so a restart finds them without the lookup.
@(private = "file")
load_image_request :: proc(
	client: ^http.Client,
	request: Image_Request,
	visitor: string,
) -> ^sdl.Surface {
	cache := image_loader.cache
	source := request.source
	if request.target > 0 && strings.has_prefix(source, "UC") {
		if surface := read_cached_image(cache, source, request.target); surface != nil {
			return surface
		}
		url := avatar_url(source)
		if url == "" {
			url = yt.channel_avatar(client, source, visitor)
			if url == "" {return nil}
			remember_avatar_url(source, url)
		}
		defer delete(url)
		return load_cached_image(cache, client, url, request.target, cache_source = source)
	}
	return load_cached_image(cache, client, source, request.target)
}

@(private = "file")
avatar_url :: proc(channel: string) -> string {
	sync.guard(&image_loader.mutex)
	return strings.clone(image_loader.avatars[channel])
}

@(private = "file")
remember_avatar_url :: proc(channel, url: string) {
	sync.guard(&image_loader.mutex)
	if channel in image_loader.avatars {return}
	image_loader.avatars[strings.clone(channel)] = strings.clone(url)
}
