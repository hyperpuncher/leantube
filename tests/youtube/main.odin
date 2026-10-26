package main

import "../../src/http"
import "../../src/model"
import yt "../../src/youtube"
import "core:fmt"
import "core:os"
import "core:strings"

// Explicit live check. Print metadata and status only, never signed URLs.
main :: proc() {
	client, error := http.open()
	assert(error == nil, "HTTPS setup failed")
	defer http.close(&client)
	catalog, search_error, visitor := yt.search(&client, "Linus Tech Tips")
	assert(search_error == .None, "native search failed")
	defer model.catalog_destroy(&catalog)
	defer delete(visitor)
	assert(visitor != "", "search did not provide an anonymous session")
	assert(len(catalog.videos) > 0)
	fmt.println("native search results:", len(catalog.videos))
	bytes := yt.thumbnail(&client, catalog.videos[0].id)
	assert(len(bytes) > 0, "thumbnail fetch failed")
	delete(bytes)
	stream, player_error := yt.resolve(&client, "C5WDBA2i9nE")
	assert(player_error == .None, "native player resolution failed")
	defer delete(stream.url)
	response, cdn_error := http.request(&client, stream.url, headers = {"Range: bytes=0-1023"})
	assert(cdn_error == nil && response.status == 206, "resolved CDN stream could not be read")
	defer delete(response.body)
	fmt.println("native combined stream verified; height:", stream.height)
	defer yt.remove_local_hls()
	for id in ([]string{"C5WDBA2i9nE", "DN953UW8iJ8"}) {
		hls, hls_error := yt.resolve(&client, id, visitor)
		defer delete(hls.url)
		defer delete(hls.audio_url)
		assert(hls_error == .None, "native HLS resolution failed")
		assert(hls.height == 0, "a master playlist must not claim the displayed resolution")
		assert(strings.has_prefix(hls.url, "file://"), "HLS master was not localized")
		assert(hls.audio_url != "", "original AAC audio was not found")
		master, master_error := os.read_entire_file_from_path(yt.LOCAL_HLS_PATH, context.allocator)
		defer delete(master)
		assert(master_error == nil, "local HLS master could not be read")
		text := string(master[:])
		assert(
			strings.has_prefix(text, "#EXTM3U") && strings.contains(text, "RESOLUTION=3840x2160"),
			"expected a 4k HLS master",
		)
		assert(strings.contains(text, "vp09") && strings.contains(text, "mp4a.40.2"))
		audio, audio_error := os.read_entire_file_from_path(
			yt.LOCAL_AUDIO_HLS_PATH,
			context.allocator,
		)
		defer delete(audio)
		assert(audio_error == nil, "local HLS audio playlist could not be read")
		audio_text := string(audio[:])
		assert(
			strings.contains(audio_text, "#EXT-X-MAP") &&
			strings.contains(audio_text, "#EXT-X-BYTERANGE"),
			"audio playlist has no byte-range segments",
		)
		fmt.println(
			"native HLS master verified; original AAC track; video:",
			id,
			"audio bytes:",
			hls.audio_content_size,
		)
	}
}
