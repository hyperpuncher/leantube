#+test
package youtube

import "core:testing"

@(test)
hls_attribute_removal_keeps_the_other_attributes_valid :: proc(t: ^testing.T) {
	line := `#EXT-X-STREAM-INF:BANDWIDTH=1,AUDIO="a",SUBTITLES="s",CLOSED-CAPTIONS=NONE`
	without_audio := without_attribute(line, "AUDIO")
	defer delete(without_audio)
	testing.expect_value(
		t,
		without_audio,
		`#EXT-X-STREAM-INF:BANDWIDTH=1,SUBTITLES="s",CLOSED-CAPTIONS=NONE`,
	)
	without_subs := without_attribute(without_audio, "SUBTITLES")
	defer delete(without_subs)
	testing.expect_value(t, without_subs, `#EXT-X-STREAM-INF:BANDWIDTH=1,CLOSED-CAPTIONS=NONE`)
	without_last := without_attribute(without_subs, "CLOSED-CAPTIONS")
	defer delete(without_last)
	testing.expect_value(t, without_last, `#EXT-X-STREAM-INF:BANDWIDTH=1`)
}

@(test)
hls_attributes_and_resolution_are_parsed_without_urls :: proc(t: ^testing.T) {
	line := `#EXT-X-STREAM-INF:BANDWIDTH=55873126,RESOLUTION=3840x1920,CODECS="vp09.00.50.08,mp4a.40.2"`
	testing.expect_value(t, attribute(line, "RESOLUTION"), "3840x1920")
	testing.expect_value(t, attribute(line, "CODECS"), "vp09.00.50.08,mp4a.40.2")
	testing.expect_value(t, resolution_height("3840x1920"), 1920)
	testing.expect_value(t, resolution_height("bad"), 0)
}
