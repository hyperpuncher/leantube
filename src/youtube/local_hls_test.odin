#+test
package youtube

import "core:strings"
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
hls_prefers_mp4_video_at_equal_resolution_without_lowering_quality :: proc(t: ^testing.T) {
	lines := []string {
		`#EXT-X-STREAM-INF:RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2"`,
		"https://media.example/avc",
		`#EXT-X-STREAM-INF:RESOLUTION=1920x1080,CODECS="vp09.00.40.08,mp4a.40.2"`,
		"https://media.example/vp9",
	}
	testing.expect_value(t, hls_variant_index(lines), 2)
	portrait := []string {
		`#EXT-X-STREAM-INF:RESOLUTION=1080x1920,CODECS="avc1.640028,mp4a.40.2"`,
		"https://media.example/portrait-avc",
		`#EXT-X-STREAM-INF:RESOLUTION=1080x1920,CODECS="vp09.00.40.08,mp4a.40.2"`,
		"https://media.example/portrait-vp9",
	}
	testing.expect_value(t, hls_variant_index(portrait), 2)
	higher := []string {
		`#EXT-X-STREAM-INF:RESOLUTION=3840x2160,CODECS="avc1.640033,mp4a.40.2"`,
		"https://media.example/higher",
		lines[2],
		lines[3],
	}
	testing.expect_value(t, hls_variant_index(higher), 0)
}

@(test)
hdr_types_map_to_the_display_metadata_names :: proc(t: ^testing.T) {
	testing.expect_value(t, hdr_from_range("PQ"), Hdr.Hdr10)
	testing.expect_value(t, hdr_from_range("HLG"), Hdr.Hlg)
	testing.expect_value(t, hdr_from_range("SDR"), Hdr.None)
	testing.expect_value(t, hdr_from_range(""), Hdr.None)
	testing.expect_value(t, hdr_label(.Hdr10), "HDR10")
	testing.expect_value(t, hdr_label(.Hlg), "HLG")
	testing.expect_value(t, hdr_label(.None), "")
}

@(test)
hls_prefers_hdr_and_vp9_without_lowering_quality :: proc(t: ^testing.T) {
	lines := []string {
		`#EXT-X-STREAM-INF:RESOLUTION=3840x2160,CODECS="avc1.640033,mp4a.40.2",VIDEO-RANGE=SDR`,
		"https://media.example/avc",
		`#EXT-X-STREAM-INF:RESOLUTION=3840x2160,CODECS="vp09.00.50.08,mp4a.40.2",VIDEO-RANGE=SDR`,
		"https://media.example/vp9",
		`#EXT-X-STREAM-INF:RESOLUTION=3840x2160,CODECS="vp09.02.51.10,mp4a.40.2",VIDEO-RANGE=PQ`,
		"https://media.example/vp9-hdr",
	}
	testing.expect_value(t, hls_variant_index(lines), 4)
	// A taller SDR variant still beats a smaller HDR one.
	higher := []string {
		lines[4],
		lines[5],
		`#EXT-X-STREAM-INF:RESOLUTION=1920x1080,CODECS="vp09.02.41.10,mp4a.40.2",VIDEO-RANGE=PQ`,
		"https://media.example/vp9-hdr-small",
	}
	testing.expect_value(t, hls_variant_index(higher), 0)
	// HLG and PQ rank the same, and VP9 breaks the tie.
	hlg := []string {
		lines[0],
		lines[1],
		`#EXT-X-STREAM-INF:RESOLUTION=3840x2160,CODECS="vp09.02.51.10,mp4a.40.2",VIDEO-RANGE=HLG`,
		"https://media.example/vp9-hlg",
	}
	testing.expect_value(t, hls_variant_index(hlg), 2)
}

@(test)
hls_uses_only_an_absolute_master_audio_group :: proc(t: ^testing.T) {
	lines := []string {
		`#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="234",NAME="Default",DEFAULT=YES,AUTOSELECT=YES,URI="https://media.example/audio.m3u8"`,
		`#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="233",NAME="Default",URI="/relative/audio.m3u8"`,
		`#EXT-X-STREAM-INF:RESOLUTION=3840x2160,CODECS="vp09.00.50.08",AUDIO="234"`,
		"https://media.example/video",
	}
	group := audio_group_lines(lines, "234")
	defer delete(group)
	if !testing.expect_value(t, len(group), 1) {return}
	testing.expect(t, strings.contains(group[0], `GROUP-ID="234"`))
	testing.expect_value(t, len(audio_group_lines(lines, "233")), 0)
	testing.expect_value(t, len(audio_group_lines(lines, "missing")), 0)
}

@(test)
hls_attributes_and_resolution_are_parsed_without_urls :: proc(t: ^testing.T) {
	line := `#EXT-X-STREAM-INF:BANDWIDTH=55873126,RESOLUTION=3840x1920,CODECS="vp09.00.50.08,mp4a.40.2"`
	testing.expect_value(t, attribute(line, "RESOLUTION"), "3840x1920")
	testing.expect_value(t, attribute(line, "CODECS"), "vp09.00.50.08,mp4a.40.2")
	testing.expect_value(t, resolution_height("3840x1920"), 1920)
	testing.expect_value(t, resolution_height("bad"), 0)
}
