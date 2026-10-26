package main

import "../../src/http"
import "../../src/model"
import sb "../../src/sponsorblock"
import yt "../../src/youtube"
import "core:fmt"

// Explicit live check. No playback, submissions, or skip-count reports.
main :: proc() {
	client, error := http.open()
	assert(error == nil, "HTTPS setup failed")
	defer http.close(&client)
	catalog, search_error, visitor := yt.search(&client, "Linus Tech Tips")
	assert(search_error == .None, "channel video search failed")
	defer model.catalog_destroy(&catalog)
	defer delete(visitor)
	checked, groups: int
	for video in catalog.videos {
		if video.channel != "Linus Tech Tips" {continue}
		segments := sb.fetch(&client, video.id)
		defer delete(segments)
		if len(segments) == 0 {continue}
		fmt.println("Linus Tech Tips video:", video.id, video.title)
		for segment in segments {
			duration :=
				segment.video_duration_ms > 0 ? segment.video_duration_ms : video.duration_ms
			target := sb.skip_target(segments[:], segment.start_ms, duration)
			if target < 0 {continue}
			assert(target >= segment.end_ms && target <= duration, "invalid sponsor skip target")
			fmt.printf(
				"  sponsor group: %.3f -> %.3f seconds\n",
				segment.start_ms / 1000,
				target / 1000,
			)
			sb.mark_skipped(segments[:], segment.start_ms, target)
			assert(
				sb.skip_target(segments[:], segment.start_ms, duration) < 0,
				"sponsor skip repeated",
			)
			groups += 1
		}
		checked += 1
		if checked == 3 {break}
	}
	assert(checked > 0 && groups > 0, "no usable Linus Tech Tips sponsor segments were found")
	fmt.printf(
		"live SponsorBlock check passed: %d videos, %d sponsor groups; playback was not tested\n",
		checked,
		groups,
	)
}
