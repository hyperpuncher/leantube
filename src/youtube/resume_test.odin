#+test
package youtube

import "../model"
import "core:encoding/json"
import "core:testing"

@(test)
resume_start_prefers_an_exact_timestamp_over_a_rounded_percentage :: proc(t: ^testing.T) {
	for fixture in ([]struct {
			exact:       f64,
			known:       bool,
			duration_ms: f64,
			percent:     f32,
			expected:    f64,
		}{{123500, true, 600000, 20, 123500}, {0, true, 600000, 35, 0}, {30000, true, 600000, 5, 30000}, {0, false, 600000, 35, 210000}, {0, false, 600000, 10, 0}, {0, false, 600000, 11, 66000}, {0, false, 0, 35, 0}, {123500, true, 0, 0, 123500}, {599000, true, 600000, 100, 0}}) {
		testing.expect_value(
			t,
			resume_start(fixture.exact, fixture.known, fixture.duration_ms, fixture.percent),
			fixture.expected,
		)
	}
}

@(test)
resume_timestamp_comes_only_from_the_matching_playback_action :: proc(t: ^testing.T) {
	for fixture in ([]struct {
			command:  string,
			expected: f64,
		}{{`{"watchEndpoint":{"videoId":"aqz-KE-bpKQ","startTimeSeconds":123.5}}`, 123500}, {`{"watchEndpoint":{"videoId":"aqz-KE-bpKQ","startTimeSeconds":"42"}}`, 42000}, {`{"watchEndpoint":{"videoId":"different","startTimeSeconds":42}}`, 0}, {`{"watchEndpoint":{"videoId":"aqz-KE-bpKQ","startTimeSeconds":-1}}`, 0}, {`{"watchEndpoint":{"videoId":"aqz-KE-bpKQ","startTimeSeconds":601}}`, 0}, {`{"watchEndpoint":{"videoId":"aqz-KE-bpKQ","startTimeSeconds":"NaN"}}`, 0}, {`{"watchEndpoint":{"videoId":"aqz-KE-bpKQ"}}`, 0}}) {
		value, error := json.parse(fixture.command)
		testing.expect_value(t, error, json.Error.None)
		card := model.Video {
			id          = "aqz-KE-bpKQ",
			duration_ms = 600000,
		}
		read_resume_position(&card, value)
		testing.expect_value(t, card.resume_ms, fixture.expected)
		json.destroy_value(value)
	}
}

@(test)
web_and_lockup_cards_read_resume_from_their_own_action_only :: proc(t: ^testing.T) {
	for fixture in ([]struct {
			data:     string,
			expected: f64,
		}{{`{"videoRenderer":{"videoId":"aqz-KE-bpKQ","title":{"simpleText":"Resume"},"lengthText":{"simpleText":"10:00"},"thumbnailOverlays":[{"thumbnailOverlayResumePlaybackRenderer":{"percentDurationWatched":20}}],"navigationEndpoint":{"watchEndpoint":{"videoId":"aqz-KE-bpKQ","startTimeSeconds":123.5}}}}`, 123500}, {`{"lockupViewModel":{"contentId":"aqz-KE-bpKQ","contentType":"LOCKUP_CONTENT_TYPE_VIDEO","metadata":{"lockupMetadataViewModel":{"title":{"content":"Resume"}}},"contentImage":{"thumbnailViewModel":{"overlays":[{"thumbnailOverlayProgressBarViewModel":{"startPercent":20}},{"thumbnailBottomOverlayViewModel":{"badges":[{"thumbnailBadgeViewModel":{"text":"10:00"}}]}}]}},"rendererContext":{"commandContext":{"onTap":{"innertubeCommand":{"watchEndpoint":{"videoId":"aqz-KE-bpKQ","startTimeSeconds":123.5}}}}}}}`, 123500}, {`{"videoRenderer":{"videoId":"aqz-KE-bpKQ","title":{"simpleText":"Resume"},"lengthText":{"simpleText":"10:00"},"thumbnailOverlays":[{"thumbnailOverlayResumePlaybackRenderer":{"percentDurationWatched":20}}],"menu":{"watchEndpoint":{"videoId":"aqz-KE-bpKQ","startTimeSeconds":123.5}}}}`, 120000}}) {
		value, error := json.parse(fixture.data)
		testing.expect_value(t, error, json.Error.None)
		catalog: model.Catalog
		collect_videos(value, &catalog)
		collect_lockups(value, &catalog)
		json.destroy_value(value)
		if testing.expect_value(t, len(catalog.videos), 1) {
			testing.expect_value(t, catalog.videos[0].watched_percent, f32(20))
			testing.expect_value(t, catalog.videos[0].resume_ms, fixture.expected)
		}
		model.catalog_destroy(&catalog)
	}
}
