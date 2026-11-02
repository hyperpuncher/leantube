#+test
package youtube

import "core:testing"

@(test)
player_selects_highest_supported_resolution_frame_rate_and_hdr :: proc(t: ^testing.T) {
	data := `{"videoDetails":{"lengthSeconds":"123","channelId":"UC-example","title":"Example video"},"playabilityStatus":{"status":"OK"},"streamingData":{"adaptiveFormats":[
	{"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":128000,"xtags":"ChEKBWFjb250EghvcmlnaW5hbAoNCgRsYW5nEgVlbi1VUw","audioTrack":{"audioIsDefault":false},"url":"https://media.example/original"},
	{"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":256000,"xtags":"ChQKBWFjb250EgtkdWJiZWQtYXV0bwoNCgRsYW5nEgVkZS1ERQ","audioTrack":{"audioIsDefault":true},"url":"https://media.example/dub"},
	{"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":256000,"isDrc":true,"url":"https://media.example/drc"},
	{"mimeType":"video/webm; codecs=\"vp9\"","width":3840,"height":2160,"fps":30,"bitrate":100,"url":"https://media.example/30"},
	{"mimeType":"video/webm; codecs=\"vp9\"","width":3840,"height":2160,"fps":60,"bitrate":200,"url":"https://media.example/sdr"},
	{"mimeType":"video/webm; codecs=\"vp9.2\"","width":3840,"height":2160,"fps":60,"bitrate":100,"colorInfo":{"transferCharacteristics":"COLOR_TRANSFER_CHARACTERISTICS_SMPTEST2084"},"url":"https://media.example/hdr"},
	{"mimeType":"video/mp4; codecs=\"av01\"","width":7680,"height":4320,"fps":60,"url":"https://media.example/av1"},
	{"mimeType":"video/webm; codecs=\"vp9\"","width":7680,"height":4320,"fps":60,"url":"http://media.example/insecure"}
	]}}`
	limits := []Video_Limit{{"vp9", 4096, 2304, 60}, {"av1", 0, 0, 0}}
	stream, error := parse_player(data, limits)
	defer stream_destroy(&stream)
	testing.expect_value(t, error, .None)
	testing.expect_value(t, stream.channel_id, "UC-example")
	testing.expect_value(t, stream.title, "Example video")
	testing.expect_value(t, stream.url, "https://media.example/hdr")
	testing.expect_value(t, stream.audio_url, "https://media.example/original")
	testing.expect(t, stream.width == 3840 && stream.height == 2160)
	testing.expect_value(t, stream.duration_ms, f64(123000))
	// A more capable device is not limited to the tested TV's resolution.
	larger, larger_error := parse_player(data, {{"av1", 7680, 4320, 60}})
	defer stream_destroy(&larger)
	testing.expect_value(t, larger_error, .None)
	testing.expect_value(t, larger.width, 7680)
}

@(test)
combined_audio_does_not_reduce_separate_video_quality :: proc(t: ^testing.T) {
	stream, error := parse_player(
		`{"playabilityStatus":{"status":"OK"},"streamingData":{
	"adaptiveFormats":[{"mimeType":"video/webm; codecs=\"vp9\"","width":3840,"height":2160,"fps":60,"url":"https://media.example/video"}],
	"formats":[{"mimeType":"video/mp4; codecs=\"avc1, mp4a.40.2\"","width":640,"height":360,"fps":30,"url":"https://media.example/audio"}]}}`,
	)
	defer stream_destroy(&stream)
	testing.expect_value(t, error, .None)
	testing.expect_value(t, stream.width, 3840)
	testing.expect_value(t, stream.audio_url, "https://media.example/audio")
}

@(test)
no_supported_video_does_not_return_audio_or_manifest_as_video :: proc(t: ^testing.T) {
	stream, error := parse_player(
		`{"playabilityStatus":{"status":"OK"},"streamingData":{
	"hlsManifestUrl":"https://media.example/master.m3u8",
	"adaptiveFormats":[{"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":128000,"url":"https://media.example/audio"},
	{"mimeType":"video/mp4; codecs=\"av01\"","width":3840,"height":2160,"fps":60,"url":"https://media.example/video"}]}}`,
		{{"av1", 0, 0, 0}},
	)
	testing.expect_value(t, error, .No_Direct_Stream)
	testing.expect(t, stream.url == "" && stream.audio_url == "")
}

@(test)
legacy_profile_caps_firmware_config_to_verified_formats :: proc(t: ^testing.T) {
	config := `{"videoCodecs":[
	{"name":"H.264","maxWidth":4096,"maxHeight":2160,"maxFrameRate":60},
	{"name":"HEVC","maxWidth":4096,"maxHeight":2160,"maxFrameRate":60},
	{"name":"VP9","maxWidth":4096,"maxHeight":2160,"maxFrameRate":60},
	{"name":"AV1","maxWidth":3840,"maxHeight":2160,"maxFrameRate":60}]}`
	h264, h264_ok := legacy_video_limit(config, "h264")
	testing.expect(t, h264_ok)
	testing.expect_value(t, h264, Video_Limit{"h264", 1920, 1080, 60})
	vp9, vp9_ok := legacy_video_limit(config, "vp9")
	testing.expect(t, vp9_ok)
	testing.expect_value(t, vp9, Video_Limit{"vp9", 3840, 2160, 60})
	_, hevc_ok := legacy_video_limit(config, "hevc")
	testing.expect(t, !hevc_ok)
	_, av1_ok := legacy_video_limit(config, "av1")
	testing.expect(t, !av1_ok)
	// A smaller firmware entry lowers the verified profile.
	small, small_ok := legacy_video_limit(
		`{"videoCodecs":[{"name":"VP9","maxWidth":1920,"maxHeight":1088,"maxFrameRate":30}]}`,
		"vp9",
	)
	testing.expect(t, small_ok)
	testing.expect_value(t, small, Video_Limit{"vp9", 1920, 1088, 30})
	// Absent, malformed or incomplete entries keep the conservative fallback.
	_, absent_ok := legacy_video_limit(
		`{"videoCodecs":[{"name":"H.264","maxWidth":1920,"maxHeight":1080,"maxFrameRate":60}]}`,
		"vp9",
	)
	testing.expect(t, !absent_ok)
	_, malformed_ok := legacy_video_limit(`{`, "h264")
	testing.expect(t, !malformed_ok)
	_, incomplete_ok := legacy_video_limit(
		`{"videoCodecs":[{"name":"VP9","maxWidth":3840}]}`,
		"vp9",
	)
	testing.expect(t, !incomplete_ok)
	_, empty_ok := legacy_video_limit("", "h264")
	testing.expect(t, !empty_ok)
	uhd_vp9, uhd_vp9_ok := legacy_uhd_limit("vp9")
	testing.expect(t, uhd_vp9_ok)
	testing.expect_value(t, uhd_vp9, Video_Limit{"vp9", 3840, 2160, 60})
	uhd_h264, uhd_h264_ok := legacy_uhd_limit("h264")
	testing.expect(t, uhd_h264_ok)
	testing.expect_value(t, uhd_h264, Video_Limit{"h264", 1920, 1080, 60})
	_, uhd_hevc_ok := legacy_uhd_limit("hevc")
	testing.expect(t, !uhd_hevc_ok)
	_, uhd_av1_ok := legacy_uhd_limit("av1")
	testing.expect(t, !uhd_av1_ok)
}

@(test)
legacy_profile_selects_vp9_4k60_and_rejects_av1 :: proc(t: ^testing.T) {
	data := `{"playabilityStatus":{"status":"OK"},"streamingData":{"adaptiveFormats":[
	{"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":128000,"url":"https://media.example/audio"},
	{"mimeType":"video/mp4; codecs=\"avc1.640028\"","width":1920,"height":1080,"fps":30,"url":"https://media.example/h264-30"},
	{"mimeType":"video/mp4; codecs=\"avc1.640033\"","width":1920,"height":1080,"fps":60,"url":"https://media.example/h264"},
	{"mimeType":"video/webm; codecs=\"vp9\"","width":3840,"height":2160,"fps":60,"url":"https://media.example/vp9"},
	{"mimeType":"video/mp4; codecs=\"av01.0.13M.08\"","width":7680,"height":4320,"fps":60,"url":"https://media.example/av1"}
	]}}`
	limits := []Video_Limit {
		{"h264", 1920, 1080, 60},
		{"hevc", 0, 0, 0},
		{"vp9", 3840, 2160, 60},
		{"av1", 0, 0, 0},
	}
	stream, error := parse_player(data, limits)
	defer stream_destroy(&stream)
	testing.expect_value(t, error, .None)
	testing.expect_value(t, stream.url, "https://media.example/vp9")
	fallback, fallback_error := parse_player(data, {{"h264", 1920, 1080, 30}})
	defer stream_destroy(&fallback)
	testing.expect_value(t, fallback_error, .None)
	testing.expect_value(t, fallback.url, "https://media.example/h264-30")
	h264, h264_error := parse_player(data, limits[:1])
	defer stream_destroy(&h264)
	testing.expect_value(t, h264_error, .None)
	testing.expect_value(t, h264.url, "https://media.example/h264")
}
