#+test
package model

import "core:encoding/json"
import "core:testing"

@(test)
original_audio_language_selects_a_matching_track_index :: proc(t: ^testing.T) {
	value, err := json.parse(
		`{"programInfo":[{"duration":1000,"audioTrackInfo":[{"language":"ja"},{"language":"en-US"},{"language":"en"}]}]}`,
	)
	if !testing.expect(t, err == .None) {return}
	defer json.destroy_value(value)
	source, ok := value.(json.Object)
	if !testing.expect(t, ok) {return}
	testing.expect_value(t, audio_track_index(source, "ja"), 0)
	testing.expect_value(t, audio_track_index(source, "en"), 1)
	for invalid in ([]string{"", "fr", "e"}) {
		testing.expect_value(t, audio_track_index(source, invalid), -1)
	}
	testing.expect_value(t, audio_track_index({}, "en"), -1)
}

@(test)
source_duration_uses_program_metadata :: proc(t: ^testing.T) {
	value, err := json.parse(`{"numPrograms":1,"programInfo":[{"duration":634578}]}`)
	if !testing.expect(t, err == .None) {return}
	defer json.destroy_value(value)
	source, ok := value.(json.Object)
	if !testing.expect(t, ok) {return}
	testing.expect_value(t, source_duration(source), f64(634578))
}

@(test)
source_duration_rejects_unknown_values :: proc(t: ^testing.T) {
	for fixture in ([]string{`{}`, `{"programInfo":[]}`, `{"programInfo":[null]}`, `{"programInfo":[{}]}`, `{"programInfo":[{"duration":0}]}`, `{"programInfo":[{"duration":-1}]}`, `{"programInfo":[{"duration":"unknown"}]}`}) {
		value, err := json.parse(fixture)
		if !testing.expect(t, err == .None) {continue}
		source, ok := value.(json.Object)
		if testing.expect(t, ok) {testing.expect_value(t, source_duration(source), f64(0))}
		json.destroy_value(value)
	}
}
