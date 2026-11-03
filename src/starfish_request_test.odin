package main

import "core:encoding/json"
import "core:testing"

@(test)
starfish_load_keeps_the_verified_native_request :: proc(t: ^testing.T) {
	request := starfish_load_request(
		{
			app_id = "org.hyperpuncher.leantube",
			video_codec = "VP9",
			width = 3840,
			height = 2160,
			fps_value = 60000,
			fps_scale = 1001,
			fps = 60000.0 / 1001,
			target_seconds = 84.384,
			audio_rate = 44100,
			audio_channels = 2,
		},
	)
	data, err := json.marshal(request)
	if !testing.expect(t, err == nil) {return}
	defer delete(data)
	// Captured from the previous formatter, before replacing it with this request type.
	fixture :: #load("../tests/native/starfish-load.json", string)
	canonical: [2][]u8
	defer for bytes in canonical {delete(bytes)}
	for text, i in ([2]string{fixture, string(data)}) {
		value, parse_error := json.parse(text)
		if !testing.expect(t, parse_error == .None) {return}
		defer json.destroy_value(value)
		encoded, marshal_error := json.marshal(value, {sort_maps_by_key = true})
		if !testing.expect(t, marshal_error == nil) {return}
		canonical[i] = encoded
	}
	testing.expect(
		t,
		string(canonical[0]) == string(canonical[1]),
		"the native load fields, values, and units must not change",
	)
}
