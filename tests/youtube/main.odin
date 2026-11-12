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
	catalog, search_error, visitor := yt.search(&client, "Linus Tech Tips")
	assert(search_error == .None, "native search failed")
	defer model.catalog_destroy(&catalog)
	defer delete(visitor)
	assert(visitor != "", "search did not provide an anonymous session")
	assert(len(catalog.videos) > 0)
	fmt.println("native search results:", len(catalog.videos))
	assert(catalog.continuation != "", "search did not provide a next page")
	next, next_error, next_visitor := yt.search(
		&client,
		catalog.query,
		catalog.continuation,
		visitor,
	)
	defer model.catalog_destroy(&next)
	defer delete(next_visitor)
	assert(next_error == .None && len(next.videos) > 0, "native search continuation failed")
	fmt.println("native search next-page results:", len(next.videos))
	bytes := yt.thumbnail(&client, catalog.videos[0].id)
	assert(len(bytes) > 0, "thumbnail fetch failed")
	delete(bytes)
	for id in ([]string{"C5WDBA2i9nE", "DN953UW8iJ8"}) {
		stream, player_error := yt.resolve(&client, id, visitor)
		assert(player_error == .None, "direct source resolution failed")
		defer yt.stream_destroy(&stream)
		assert(stream.width > 0 && stream.height > 0 && stream.audio_url != "")
		for url in ([]string{stream.url, stream.audio_url}) {
			response, cdn_error := http.request(
				&client,
				url,
				headers = {"Range: bytes=0-1023"},
				follow_redirects = true,
			)
			defer delete(response.body)
			assert(
				cdn_error == nil && response.status == 206,
				"resolved CDN source could not be read",
			)
		}
		fmt.printf(
			"direct video and original AAC verified; size=%dx%d\n",
			stream.width,
			stream.height,
		)
	}
}
