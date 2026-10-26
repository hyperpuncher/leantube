package main

import "../../src/http"
import "../../src/model"
import yt "../../src/youtube"
import "core:fmt"
import "core:strings"

// Explicit live check. Print metadata and status only, never signed URLs.
main :: proc() {
	client, error := http.open()
	assert(error == nil, "HTTPS setup failed")
	defer http.close(&client)
	catalog, search_error, visitor := yt.search(&client, "Blender open movies")
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
	for id in ([]string{"C5WDBA2i9nE", "DN953UW8iJ8"}) {
		hls, hls_error := yt.resolve(&client, id, visitor)
		defer delete(hls.url)
		assert(hls_error == .None && hls.hls, "native HLS resolution failed")
		defer delete(hls.audio_language)
		assert(hls.height == 0, "a master playlist must not claim the displayed resolution")
		master, fetch_error := http.request(&client, hls.url)
		defer delete(master.body)
		assert(fetch_error == nil && master.status == 200, "HLS master could not be read")
		text := string(master.body[:])
		assert(
			strings.has_prefix(text, "#EXTM3U") && strings.contains(text, "RESOLUTION=3840x2160"),
			"expected a 4k HLS master",
		)
		assert(
			strings.contains(text, "vp09") && strings.contains(text, "mp4a.40.2"),
			"expected VP9 and AAC variants",
		)
		fmt.println(
			"native HLS master verified; 4k VP9/AAC advertised; original audio:",
			hls.audio_language,
			"maximum:",
			hls.max_width,
			"x",
			hls.max_height,
			"at",
			hls.max_bitrate,
			"bps; video:",
			id,
		)
		if id == "C5WDBA2i9nE" {
			assert(hls.audio_language == "en", "default audio language was not detected")
		}
		assert(hls.max_height >= 2160, "source 4k maximum was not detected")
	}
}
