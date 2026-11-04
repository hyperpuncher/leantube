#+test
package youtube

import "../model"
import "core:encoding/json"
import "core:testing"

@(test)
resume_timestamp_comes_only_from_the_matching_playback_action :: proc(t: ^testing.T) {
	for fixture in ([]struct {
			endpoint: string,
			known:    bool,
			ms:       f64,
		}{{`{"watchEndpoint":{"videoId":"aqz-KE-bpKQ","startTimeSeconds":123.5}}`, true, 123500}, {`{"watchEndpoint":{"videoId":"aqz-KE-bpKQ","startTimeSeconds":"42"}}`, true, 42000}, {`{"watchEndpoint":{"videoId":"aqz-KE-bpKQ","startTimeSeconds":0}}`, true, 0}, {`{"watchEndpoint":{"videoId":"aqz-KE-bpKQ","startTimeSeconds":600}}`, true, 600000}, {`{"watchEndpoint":{"videoId":"different","startTimeSeconds":42}}`, false, 0}, {`{"watchEndpoint":{"videoId":"aqz-KE-bpKQ","startTimeSeconds":-1}}`, false, 0}, {`{"watchEndpoint":{"videoId":"aqz-KE-bpKQ","startTimeSeconds":601}}`, false, 0}, {`{"watchEndpoint":{"videoId":"aqz-KE-bpKQ","startTimeSeconds":"NaN"}}`, false, 0}, {`{"watchEndpoint":{"videoId":"aqz-KE-bpKQ"}}`, false, 0}}) {
		value, error := json.parse(fixture.endpoint)
		testing.expect_value(t, error, json.Error.None)
		card := model.Video {
			id          = "aqz-KE-bpKQ",
			duration_ms = 600000,
		}
		read_resume_position(&card, value)
		testing.expect_value(t, card.resume_position_known, fixture.known)
		testing.expect_value(t, card.resume_position_ms, fixture.ms)
		json.destroy_value(value)
	}
}

@(test)
exact_resume_does_not_require_duration :: proc(t: ^testing.T) {
	value, error := json.parse(
		`{"watchEndpoint":{"videoId":"aqz-KE-bpKQ","startTimeSeconds":123.5}}`,
	)
	defer json.destroy_value(value)
	testing.expect_value(t, error, json.Error.None)
	card := model.Video {
		id = "aqz-KE-bpKQ",
	}
	read_resume_position(&card, value)
	testing.expect(t, card.resume_position_known)
	testing.expect_value(t, model.video_resume_position(card), f64(123500))
}

@(test)
web_and_lockup_cards_preserve_exact_resume_separately_from_percent :: proc(t: ^testing.T) {
	for fixture in ([]struct {
			data:  string,
			known: bool,
		}{{`{"videoRenderer":{"videoId":"aqz-KE-bpKQ","title":{"simpleText":"Resume"},"lengthText":{"simpleText":"10:00"},"thumbnailOverlays":[{"thumbnailOverlayResumePlaybackRenderer":{"percentDurationWatched":20}}],"navigationEndpoint":{"watchEndpoint":{"videoId":"aqz-KE-bpKQ","startTimeSeconds":123.5}}}}`, true}, {`{"lockupViewModel":{"contentId":"aqz-KE-bpKQ","contentType":"LOCKUP_CONTENT_TYPE_VIDEO","metadata":{"lockupMetadataViewModel":{"title":{"content":"Resume"}}},"contentImage":{"thumbnailViewModel":{"overlays":[{"thumbnailOverlayProgressBarViewModel":{"startPercent":20}},{"thumbnailBottomOverlayViewModel":{"badges":[{"thumbnailBadgeViewModel":{"text":"10:00"}}]}}]}},"rendererContext":{"commandContext":{"onTap":{"innertubeCommand":{"watchEndpoint":{"videoId":"aqz-KE-bpKQ","startTimeSeconds":123.5}}}}}}}`, true}, {`{"videoRenderer":{"videoId":"aqz-KE-bpKQ","title":{"simpleText":"Resume"},"lengthText":{"simpleText":"10:00"},"thumbnailOverlays":[{"thumbnailOverlayResumePlaybackRenderer":{"percentDurationWatched":20}}],"menu":{"watchEndpoint":{"videoId":"aqz-KE-bpKQ","startTimeSeconds":123.5}}}}`, false}}) {
		value, error := json.parse(fixture.data)
		testing.expect_value(t, error, json.Error.None)
		catalog: model.Catalog
		collect_videos(value, &catalog)
		collect_lockups(value, &catalog)
		json.destroy_value(value)
		if testing.expect_value(t, len(catalog.videos), 1) {
			testing.expect_value(t, catalog.videos[0].watched_percent, f32(20))
			testing.expect_value(t, catalog.videos[0].resume_position_known, fixture.known)
			testing.expect_value(
				t,
				catalog.videos[0].resume_position_ms,
				fixture.known ? f64(123500) : 0,
			)
		}
		model.catalog_destroy(&catalog)
	}
}
