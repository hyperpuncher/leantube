#+test
package main

import "core:encoding/json"
import "core:testing"

@(test)
lifecycle_event_reads_both_registration_shapes :: proc(t: ^testing.T) {
	for test in ([]struct {
			payload:  string,
			expected: string,
		}{{`{"event":"relaunch"}`, "relaunch"}, {`{"message":"relaunch"}`, "relaunch"}, {`{"message":"close"}`, "close"}, {`{"event":"close","message":"relaunch"}`, "close"}, {`{"event":42,"message":"close"}`, "close"}, {`{"message":42}`, ""}, {`{}`, ""}}) {
		value, error := json.parse(test.payload)
		testing.expect_value(t, error, json.Error.None)
		root, ok := value.(json.Object)
		testing.expect(t, ok)
		testing.expect_value(t, lifecycle_event(root), test.expected)
		json.destroy_value(value)
	}
}

@(test)
launch_parameters_accept_wrapped_and_flat_legacy_arguments :: proc(t: ^testing.T) {
	for payload in ([]string{`{"parameters":{"action":"open","videoId":"aqz-KE-bpKQ","position":30}}`, `{"@system_native_app":true,"position":30,"nid":"org.hyperpuncher.leantube","action":"open","videoId":"aqz-KE-bpKQ"}`}) {
		value, error := json.parse(payload)
		testing.expect_value(t, error, json.Error.None)
		root, _ := value.(json.Object)
		command, valid := parse_control(launch_parameters(root))
		testing.expect(t, valid)
		testing.expect_value(t, command.action, Control_Action.Open)
		testing.expect_value(t, string(command.video_id[:]), "aqz-KE-bpKQ")
		testing.expect_value(t, command.position_ms, f64(30000))
		json.destroy_value(value)
	}
	value, _ := json.parse(`{"parameters":{}}`)
	root, _ := value.(json.Object)
	_, valid := parse_control(launch_parameters(root))
	testing.expect(t, !valid)
	json.destroy_value(value)
}
