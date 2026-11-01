#+test
package youtube

import "core:testing"

@(test)
player_selects_highest_supported_resolution_frame_rate_and_hdr :: proc(t: ^testing.T) {
	data := `{"videoDetails":{"lengthSeconds":"123"},"playabilityStatus":{"status":"OK"},"streamingData":{"adaptiveFormats":[
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
	defer delete(stream.url); defer delete(stream.audio_url)
	testing.expect_value(t, error, .None)
	testing.expect_value(t, stream.url, "https://media.example/hdr")
	testing.expect_value(t, stream.audio_url, "https://media.example/original")
	testing.expect(t, stream.width == 3840 && stream.height == 2160)
	testing.expect_value(t, stream.duration_ms, f64(123000))
	// A more capable device is not limited to the tested TV's resolution.
	larger, larger_error := parse_player(data, {{"av1", 7680, 4320, 60}})
	defer delete(larger.url); defer delete(larger.audio_url)
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
	defer delete(stream.url); defer delete(stream.audio_url)
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
