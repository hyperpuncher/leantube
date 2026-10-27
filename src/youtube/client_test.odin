#+test
package youtube

import "../model"
import "core:testing"

@(test)
search_owns_metadata_and_skips_live_duplicate_and_invalid_entries :: proc(t: ^testing.T) {
	catalog, error, visitor := parse_search(
		`{"responseContext":{"visitorData":"test-session"},"contents":{"twoColumnSearchResultsRenderer":{"primaryContents":{"items":[
		{"videoRenderer":{"videoId":"aqz-KE-bpKQ","title":{"runs":[{"text":"café "},{"text":"movie"}]},"ownerText":{"runs":[{"text":"Blender"}]},"lengthText":{"simpleText":"1:02:03"}}},
		{"videoRenderer":{"videoId":"aqz-KE-bpKQ","title":{"simpleText":"duplicate"},"lengthText":{"simpleText":"1:00"}}},
		{"videoRenderer":{"videoId":"C5WDBA2i9nE","title":{"simpleText":"live"}}},
		{"videoRenderer":{"videoId":"../private","title":{"simpleText":"invalid"},"lengthText":{"simpleText":"1:00"}}}
	]}}}}`,
		"cinéma",
	)
	defer model.catalog_destroy(&catalog)
	defer delete(visitor)
	testing.expect_value(t, visitor, "test-session")
	if !testing.expect_value(t, error, .None) {return}
	if !testing.expect_value(t, len(catalog.videos), 1) {return}
	testing.expect_value(t, catalog.query, "cinéma")
	testing.expect_value(t, catalog.videos[0].id, "aqz-KE-bpKQ")
	testing.expect_value(t, catalog.videos[0].title, "café movie")
	testing.expect_value(t, catalog.videos[0].channel, "Blender")
	testing.expect_value(t, catalog.videos[0].duration_ms, f64(3723000))
}

@(test)
empty_results_are_distinct_from_invalid_responses :: proc(t: ^testing.T) {
	catalog, error, visitor := parse_search(
		`{"contents":{"twoColumnSearchResultsRenderer":{"primaryContents":{}}}}`,
		"nothing",
	)
	defer model.catalog_destroy(&catalog)
	defer delete(visitor)
	testing.expect_value(t, error, .None)
	testing.expect_value(t, len(catalog.videos), 0)
	for data in ([]string{`{`, `{}`, `{"error":{"code":403}}`}) {
		failed, err, token := parse_search(data, "query")
		model.catalog_destroy(&failed)
		delete(token)
		testing.expect_value(t, err, .Invalid_Response)
	}
}

@(test)
tv_search_lockups_are_parsed_without_web_renderers :: proc(t: ^testing.T) {
	catalog, error, visitor := parse_search_tv(
		`{"responseContext":{"visitorData":"tv-session"},"contents":{"sectionListRenderer":{"contents":[{"shelfRenderer":{"content":{"horizontalListRenderer":{"items":[
		{"lockupViewModel":{"contentId":"DN953UW8iJ8","contentType":"LOCKUP_CONTENT_TYPE_VIDEO","metadata":{"lockupMetadataViewModel":{"title":{"content":"TV search result"},"metadata":{"contentMetadataViewModel":{"metadataRows":[{"metadataParts":[{"text":{"content":"Linus Tech Tips"}}]}]}}}},"contentImage":{"thumbnailViewModel":{"overlays":[{"thumbnailBottomOverlayViewModel":{"badges":[{"thumbnailBadgeViewModel":{"text":"15:51"}}]}}]}}}}
		]}}}}]}}}`,
		"Linus",
	)
	defer model.catalog_destroy(&catalog)
	defer delete(visitor)
	if !testing.expect_value(t, error, .None) {return}
	if !testing.expect_value(t, len(catalog.videos), 1) {return}
	testing.expect_value(t, visitor, "tv-session")
	testing.expect_value(t, catalog.videos[0].id, "DN953UW8iJ8")
	testing.expect_value(t, catalog.videos[0].title, "TV search result")
	testing.expect_value(t, catalog.videos[0].channel, "Linus Tech Tips")
	testing.expect_value(t, catalog.videos[0].duration_ms, f64(951000))
}

@(test)
search_cards_read_views_and_the_relative_date :: proc(t: ^testing.T) {
	web, web_error, web_visitor := parse_search(
		`{"contents":{"twoColumnSearchResultsRenderer":{"primaryContents":{"sectionListRenderer":{"contents":[{"videoRenderer":{"videoId":"DN953UW8iJ8","title":{"simpleText":"Web result"},"ownerText":{"runs":[{"text":"A channel"}]},"lengthText":{"simpleText":"15:51"},"viewCountText":{"simpleText":"1,234,567 views"},"publishedTimeText":{"simpleText":"2 years ago"}}}]}}}}}`,
		"query",
	)
	defer model.catalog_destroy(&web)
	defer delete(web_visitor)
	if !testing.expect_value(t, web_error, .None) {return}
	if !testing.expect_value(t, len(web.videos), 1) {return}
	testing.expect_value(t, web.videos[0].channel, "A channel")
	testing.expect_value(t, web.videos[0].meta, "1.2M views · 2 years ago")

	tv, tv_error, tv_visitor := parse_search_tv(
		`{"contents":{"sectionListRenderer":{"contents":[{"shelfRenderer":{"content":{"horizontalListRenderer":{"items":[
		{"lockupViewModel":{"contentId":"DN953UW8iJ8","contentType":"LOCKUP_CONTENT_TYPE_VIDEO","metadata":{"lockupMetadataViewModel":{"title":{"content":"TV result"},"metadata":{"contentMetadataViewModel":{"metadataRows":[{"metadataParts":[{"text":{"content":"A channel"}}]},{"metadataParts":[{"text":{"content":"1.1M views"}},{"text":{"content":"16 hours ago"}}]}]}}}},"contentImage":{"thumbnailViewModel":{"overlays":[{"thumbnailBottomOverlayViewModel":{"badges":[{"thumbnailBadgeViewModel":{"text":"15:51"}}]}}]}}}}
		]}}}}]}}}`,
		"query",
	)
	defer model.catalog_destroy(&tv)
	defer delete(tv_visitor)
	if !testing.expect_value(t, tv_error, .None) {return}
	if !testing.expect_value(t, len(tv.videos), 1) {return}
	testing.expect_value(t, tv.videos[0].channel, "A channel")
	testing.expect_value(t, tv.videos[0].meta, "1.1M views · 16 hours ago")
}

@(test)
player_selects_the_best_direct_combined_h264_stream :: proc(t: ^testing.T) {
	stream, error := parse_player(
		`{"playabilityStatus":{"status":"OK"},"streamingData":{"formats":[
		{"height":360,"mimeType":"video/mp4; codecs=\"avc1, mp4a\"","url":"https://media.example/low"},
		{"height":1080,"mimeType":"video/mp4; codecs=\"avc1, mp4a\"","signatureCipher":"not supported"},
		{"height":720,"mimeType":"video/mp4; codecs=\"avc1, mp4a\"","url":"https://media.example/high"},
		{"height":2160,"mimeType":"video/mp4; codecs=\"avc1, mp4a\"","url":"http://media.example/insecure"}
	]}}`,
	)
	defer delete(stream.url)
	testing.expect_value(t, error, .None)
	testing.expect_value(t, stream.height, 720)
	testing.expect_value(t, stream.url, "https://media.example/high")
}

@(test)
player_never_treats_sabr_or_login_responses_as_a_playable_url :: proc(t: ^testing.T) {
	for data in ([]string{`{"playabilityStatus":{"status":"LOGIN_REQUIRED"}}`, `{"playabilityStatus":{"status":"OK"},"streamingData":{"serverAbrStreamingUrl":"https://media.example/sabr","adaptiveFormats":[{"itag":315,"height":2160}]}}`}) {
		stream, error := parse_player(data)
		testing.expect(t, error != .None)
		testing.expect_value(t, stream.url, "")
		delete(stream.url)
	}
}
