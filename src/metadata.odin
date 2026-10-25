package main

import "core:encoding/json"
import "core:testing"

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
