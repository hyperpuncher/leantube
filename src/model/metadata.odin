package model

import "core:encoding/json"
import "core:strings"

number :: proc(value: json.Value) -> (f64, bool) {
	#partial switch v in value {
	case json.Float:
		return f64(v), true
	case json.Integer:
		return f64(v), true
	}
	return 0, false
}

source_duration :: proc(source: json.Object) -> f64 {
	programs, found := source["programInfo"].(json.Array)
	if !found || len(programs) == 0 {return 0}
	program, valid := programs[0].(json.Object)
	if !valid {return 0}
	duration, numeric := number(program["duration"])
	return numeric && duration > 0 ? duration : 0
}

// HLS audio renditions may mark no track as default, and the decoder then
// falls back to the first rendition. Match the reported original language to
// the media service audio track order.
audio_track_index :: proc(source: json.Object, language: string) -> int {
	if language == "" {return -1}
	programs, has_programs := source["programInfo"].(json.Array)
	if !has_programs || len(programs) == 0 {return -1}
	program, valid_program := programs[0].(json.Object)
	if !valid_program {return -1}
	tracks, has_tracks := program["audioTrackInfo"].(json.Array)
	if !has_tracks {return -1}
	for track, index in tracks {
		entry, is_entry := track.(json.Object)
		if !is_entry {continue}
		code, has_language := entry["language"].(json.String)
		if !has_language {continue}
		value := string(code)
		if value == language ||
		   (strings.has_prefix(value, language) &&
				   len(value) > len(language) &&
				   value[len(language)] == '-') {return index}
	}
	return -1
}
