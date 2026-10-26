package main

import "../../src/http"
import "../../src/model"
import yt "../../src/youtube"
import "core:fmt"

// Explicit live check. Print metadata and status only, never signed URLs.
main :: proc() {
	client, error := http.open()
	assert(error == nil, "HTTPS setup failed")
	defer http.close(&client)
	catalog, search_error := yt.search(&client, "Blender open movies")
	assert(search_error == .None, "native search failed")
	defer model.catalog_destroy(&catalog)
	assert(len(catalog.videos) > 0)
	fmt.println("native search results:", len(catalog.videos))
	bytes := yt.thumbnail(&client, catalog.videos[0].id)
	assert(len(bytes) > 0, "thumbnail fetch failed")
	delete(bytes)
	stream, player_error := yt.resolve(&client, "C5WDBA2i9nE")
	assert(player_error == .None, "native player resolution failed")
	defer delete(stream.url)
	response, cdn_error := http.request(
		&client,
		stream.url,
		headers = {"Range: bytes=0-1023"},
		max_bytes = 1024,
	)
	assert(cdn_error == nil && response.status == 206, "resolved CDN stream could not be read")
	defer delete(response.body)
	fmt.println("native combined stream verified; height:", stream.height)
}
