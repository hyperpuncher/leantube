#+test
package main

import "./http"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync/chan"
import "core:testing"
import "core:thread"
import "core:time"
import sdl "vendor:sdl3"

image_cache_fetch_calls: int
image_cache_status: int
image_cache_fixture: []u8

image_cache_fetch :: proc(_: ^http.Client, _: string) -> (http.Response, http.Error) {
	image_cache_fetch_calls += 1
	bytes := make([dynamic]u8)
	append(&bytes, ..image_cache_fixture)
	return {status = auto_cast image_cache_status, body = bytes}, nil
}

@(test)
image_cache_reuses_original_bytes_and_recovers_from_bad_files :: proc(t: ^testing.T) {
	directory, error := os.make_directory_temp("/tmp", "leantube-images-", context.allocator)
	if !testing.expect(t, error == nil) {return}
	defer {os.remove_all(directory); delete(directory)}
	image_cache_fixture, error = os.read_entire_file("tests/ui/cover.webp", context.allocator)
	if !testing.expect(t, error == nil) {return}
	defer {delete(image_cache_fixture); image_cache_fixture = nil}
	image_cache_fetch_calls, image_cache_status = 0, 200
	cache := Image_Cache {
		directory     = directory,
		maximum_bytes = IMAGE_CACHE_BYTES,
	}
	source := "https://images.example/avatar?v=1"
	path := image_cache_path(cache, source)
	defer delete(path)
	surface := load_cached_image(cache, nil, source, fetch = image_cache_fetch)
	if !testing.expect(t, surface != nil) {return}
	testing.expect_value(t, surface.w, i32(101))
	sdl.DestroySurface(surface)
	stored, read_error := os.read_entire_file(path, context.allocator)
	if !testing.expect(t, read_error == nil) {return}
	defer delete(stored)
	testing.expect_value(t, string(stored), string(image_cache_fixture))

	// A new cache value must still work offline and at another display size.
	image_cache_status = 503
	surface = load_cached_image(
		{directory = directory, maximum_bytes = IMAGE_CACHE_BYTES},
		nil,
		source,
		32,
		image_cache_fetch,
	)
	if !testing.expect(t, surface != nil) {return}
	testing.expect_value(t, surface.w, i32(32))
	sdl.DestroySurface(surface)
	testing.expect_value(t, image_cache_fetch_calls, 1)

	if !testing.expect(t, os.write_entire_file(path, "broken image") == nil) {return}
	image_cache_status = 200
	surface = load_cached_image(cache, nil, source, fetch = image_cache_fetch)
	if !testing.expect(t, surface != nil) {return}
	sdl.DestroySurface(surface)
	testing.expect_value(t, image_cache_fetch_calls, 2)

	// HTTP errors with image bodies and invalid 200 bodies must not enter the cache.
	for status in ([]int{404, 200}) {
		image_cache_status = status
		if status == 200 {
			delete(image_cache_fixture)
			image_cache_fixture = transmute([]u8)strings.clone("not an image")
		}
		missing := "https://images.example/missing"
		testing.expect(t, load_cached_image(cache, nil, missing, fetch = image_cache_fetch) == nil)
		missing_path := image_cache_path(cache, missing)
		testing.expect(t, !os.exists(missing_path))
		delete(missing_path)
	}
}

@(test)
cached_channel_avatars_load_after_worker_restart_without_network :: proc(t: ^testing.T) {
	if !testing.expect(t, sdl.Init({.EVENTS})) {return}
	defer sdl.Quit()
	directory, error := os.make_directory_temp("/tmp", "leantube-avatars-", context.allocator)
	if !testing.expect(t, error == nil) {return}
	defer {os.remove_all(directory); delete(directory)}
	saved_directory := auth_directory
	auth_directory = directory
	defer {auth_directory = saved_directory}
	cache_directory := fmt.aprintf("%s/.cache/images", directory)
	defer delete(cache_directory)
	cache_path := strings.clone_to_cstring(cache_directory)
	defer delete(cache_path)
	if !testing.expect(t, sdl.CreateDirectory(cache_path)) {return}
	cache := Image_Cache {
		directory     = cache_directory,
		maximum_bytes = IMAGE_CACHE_BYTES,
	}
	channel :: "UC-avatar-cache-test"
	fixture, read_error := os.read_entire_file("tests/ui/cover.webp", context.allocator)
	if !testing.expect(t, read_error == nil) {return}
	defer delete(fixture)
	image_cache_fixture = fixture
	defer {image_cache_fixture = nil}
	image_cache_fetch_calls, image_cache_status = 0, 200
	surface := load_cached_image(
		cache,
		nil,
		"https://images.example/avatar",
		80,
		image_cache_fetch,
		cache_source = channel,
	)
	if !testing.expect(t, surface != nil) {return}
	sdl.DestroySurface(surface)
	testing.expect_value(t, image_cache_fetch_calls, 1)
	// Each worker starts with no URL mappings and no usable HTTP client.
	for _ in 0 ..< 2 {
		network_requests, _ = chan.create(chan.Chan(Network_Request), 1, context.allocator)
		network_results, _ = chan.create(chan.Chan(Network_Result), 1, context.allocator)
		defer stop_network()
		network_thread = thread.create(network_main)
		if !testing.expect(t, network_thread != nil) {return}
		thread.start(network_thread)
		// The worker owns these values and uses the default heap allocator.
		jobs := make([dynamic]Image_Request, 0, 1, runtime.heap_allocator())
		append(&jobs, {source = strings.clone(channel, runtime.heap_allocator()), target = 80})
		chan.send(network_requests, Network_Request{kind = .Images, images = jobs})
		result: Network_Result
		ready := false
		started := time.tick_now()
		for !ready && time.tick_since(started) < time.Second {
			result, ready = chan.try_recv(network_results)
			if !ready {time.sleep(time.Millisecond)}
		}
		defer free_network_result(&result)
		if !testing.expect(
			t,
			ready && result.surface != nil,
			"cached avatars must load without a channel lookup",
		) {return}
		testing.expect_value(t, result.kind, .Channel_Avatar)
		testing.expect_value(t, result.surface.w, i32(80))
	}
}

@(test)
image_cache_evicts_oldest_downloads_and_ignores_storage_failure :: proc(t: ^testing.T) {
	directory, error := os.make_directory_temp("/tmp", "leantube-images-", context.allocator)
	if !testing.expect(t, error == nil) {return}
	defer {os.remove_all(directory); delete(directory)}
	image_cache_fixture, error = os.read_entire_file("tests/ui/cover.webp", context.allocator)
	if !testing.expect(t, error == nil) {return}
	defer {delete(image_cache_fixture); image_cache_fixture = nil}
	image_cache_fetch_calls, image_cache_status = 0, 200
	cache := Image_Cache {
		directory     = directory,
		maximum_bytes = 2 * i64(len(image_cache_fixture)),
	}
	paths: [3]string
	defer {for path in paths {delete(path)}}
	for i in 0 ..< 3 {
		source := fmt.aprintf("https://images.example/%d", i)
		paths[i] = image_cache_path(cache, source)
		surface := load_cached_image(cache, nil, source, fetch = image_cache_fetch)
		delete(source)
		if !testing.expect(t, surface != nil) {return}
		sdl.DestroySurface(surface)
		stamp := time.unix(i64(i + 1), 0)
		if !testing.expect(t, os.chtimes(paths[i], stamp, stamp) == nil) {return}
	}
	testing.expect(t, !os.exists(paths[0]) && os.exists(paths[1]) && os.exists(paths[2]))
	cache.maximum_bytes /= 2
	testing.expect(t, trim_image_cache(cache))
	testing.expect(t, !os.exists(paths[1]) && os.exists(paths[2]))

	// A file where a cache directory should be must not stop image loading.
	cache.directory = paths[2]
	surface := load_cached_image(
		cache,
		nil,
		"https://images.example/uncached",
		fetch = image_cache_fetch,
	)
	if !testing.expect(t, surface != nil) {return}
	sdl.DestroySurface(surface)
}
