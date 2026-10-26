package model

import "core:encoding/json"

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
