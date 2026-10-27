#+test
package youtube

import "../model"
import "core:testing"

@(test)
browse_reads_only_selected_feed_and_skips_ads_live_and_duplicates :: proc(t: ^testing.T) {
	data := `{"contents":{"tvBrowseRenderer":{"content":{"tvSecondaryNavRenderer":{"tabs":[
	{"tabRenderer":{"selected":false,"content":{"tileRenderer":{"onSelectCommand":{"watchEndpoint":{"videoId":"C5WDBA2i9nE"}},"header":{"tileHeaderRenderer":{"thumbnailOverlays":[{"thumbnailOverlayTimeStatusRenderer":{"text":{"simpleText":"1:00"}}}]}},"metadata":{"tileMetadataRenderer":{"title":{"simpleText":"not selected"}}}}}}},
	{"tabRenderer":{"selected":true,"content":{"sectionListRenderer":{"contents":[
	{"adSlotRenderer":{"tileRenderer":{"onSelectCommand":{"watchEndpoint":{"videoId":"C5WDBA2i9nE"}}}}},
	{"tileRenderer":{"onSelectCommand":{"watchEndpoint":{"videoId":"DN953UW8iJ8"}},"header":{"tileHeaderRenderer":{"thumbnail":{"thumbnails":[{"url":"https://images.example/cover"}]},"thumbnailOverlays":[{"thumbnailOverlayResumePlaybackRenderer":{}},{"thumbnailOverlayTimeStatusRenderer":{"text":{"simpleText":"15:51"}}}]}},"metadata":{"tileMetadataRenderer":{"title":{"simpleText":"A video"},"lines":[{"lineRenderer":{"items":[{"lineItemRenderer":{"text":{"runs":[{"text":"A channel"}]}}}]}}]}}}},
	{"tileRenderer":{"onSelectCommand":{"watchEndpoint":{"videoId":"DN953UW8iJ8"}},"header":{"tileHeaderRenderer":{"thumbnailOverlays":[{"thumbnailOverlayTimeStatusRenderer":{"text":{"simpleText":"15:51"}}}]}},"metadata":{"tileMetadataRenderer":{"title":{"simpleText":"duplicate"}}}}},
	{"tileRenderer":{"onSelectCommand":{"watchEndpoint":{"videoId":"C5WDBA2i9nE"}},"metadata":{"tileMetadataRenderer":{"title":{"simpleText":"live"}}}}}
	],"continuations":[{"nextContinuationData":{"continuation":"next-page"}}]}}}}
	]}}}}}`
	catalog, error, visitor := parse_browse(data)
	defer model.catalog_destroy(&catalog)
	defer delete(visitor)
	if !testing.expect_value(t, error, .None) {return}
	if !testing.expect_value(t, len(catalog.videos), 1) {return}
	testing.expect_value(t, catalog.videos[0].id, "DN953UW8iJ8")
	testing.expect_value(t, catalog.videos[0].channel, "A channel")
	testing.expect_value(t, catalog.videos[0].thumbnail_url, "https://images.example/cover")
	testing.expect_value(t, catalog.continuation, "next-page")
}

@(test)
playlist_cards_keep_the_browse_target_instead_of_playing_a_video :: proc(t: ^testing.T) {
	catalog, error, visitor := parse_browse(
		`{"contents":{"gridRenderer":{"items":[{"tileRenderer":{"onSelectCommand":{"browseEndpoint":{"browseId":"VLPL-example"}},"metadata":{"tileMetadataRenderer":{"title":{"simpleText":"My playlist"}}},"header":{"tileHeaderRenderer":{"thumbnailOverlays":[{"thumbnailOverlayTimeStatusRenderer":{"text":{"simpleText":"12 videos"}}}]}}}}]}}}`,
	)
	defer model.catalog_destroy(&catalog)
	defer delete(visitor)
	if !testing.expect_value(t, error, .None) {return}
	if !testing.expect_value(t, len(catalog.videos), 1) {return}
	testing.expect_value(t, catalog.videos[0].id, "")
	testing.expect_value(t, catalog.videos[0].browse_id, "VLPL-example")
	testing.expect_value(t, catalog.videos[0].duration_label, "12 videos")
}

@(test)
empty_browse_and_continuation_responses_are_not_transport_errors :: proc(t: ^testing.T) {
	for data in ([]string{`{"contents":{"gridRenderer":{"items":[]}}}`, `{"continuationContents":{"gridContinuation":{"items":[]}}}`}) {
		catalog, error, visitor := parse_browse(data)
		defer model.catalog_destroy(&catalog)
		defer delete(visitor)
		testing.expect_value(t, error, .None)
		testing.expect_value(t, len(catalog.videos), 0)
	}
	for data in ([]string{`{`, `{}`, `{"error":{"code":403}}`}) {
		catalog, error, visitor := parse_browse(data)
		defer model.catalog_destroy(&catalog)
		defer delete(visitor)
		testing.expect_value(t, error, .Invalid_Response)
	}
}

@(test)
browse_cards_read_views_and_the_relative_date :: proc(t: ^testing.T) {
	catalog, error, visitor := parse_browse(
		`{"contents":{"gridRenderer":{"items":[{"tileRenderer":{"onSelectCommand":{"watchEndpoint":{"videoId":"DN953UW8iJ8"}},"metadata":{"tileMetadataRenderer":{"title":{"simpleText":"WAN Show"},"lines":[{"lineRenderer":{"items":[{"lineItemRenderer":{"text":{"runs":[{"text":"Linus Tech Tips"}]}}}]}},{"lineRenderer":{"items":[{"lineItemRenderer":{"text":{"simpleText":"179K views"}}},{"lineItemRenderer":{"text":{"simpleText":"•"}}},{"lineItemRenderer":{"text":{"simpleText":"Streamed 5 months ago"}}}]}}]}},"header":{"tileHeaderRenderer":{"thumbnailOverlays":[{"thumbnailOverlayTimeStatusRenderer":{"text":{"simpleText":"4:19:51"}}}]}}}}]}}}`,
	)
	defer model.catalog_destroy(&catalog)
	defer delete(visitor)
	if !testing.expect_value(t, error, .None) {return}
	if !testing.expect_value(t, len(catalog.videos), 1) {return}
	testing.expect_value(t, catalog.videos[0].channel, "Linus Tech Tips")
	testing.expect_value(t, catalog.videos[0].meta, "179K views · Streamed 5 months ago")
}
