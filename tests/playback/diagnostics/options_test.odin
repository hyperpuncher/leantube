package diagnostics

import "core:testing"

@(test)
transport_options_bound_the_sample_and_reject_invalid_ranges :: proc(t: ^testing.T) {
	for args in ([][]string{{"ffmpeg", "64", "0"}, {"curl-h3", "0", "0"}, {"curl-h3", "257", "0"}, {"curl-h3", "64", "-1"}, {"curl-h3", "1", "1.5"}, {"curl-h3", "1", "9223372036854775807"}}) {
		_, ok := transport_options(args)
		testing.expect(t, !ok)
	}
	o, ok := transport_options({"curl-h3", "64", "536870912"})
	testing.expect(t, ok && o.count == 64 && o.offset == 536870912)
}

@(test)
options_reject_invalid_inputs :: proc(t: ^testing.T) {
	for args in ([][]string{{"other", "10", "0"}, {"ffmpeg", "0", "0"}, {"ffmpeg", "10", "-1"}, {"curl-reuse", "10", "nan"}, {"ffmpeg", "10", "0", "4", "inf"}, {"ffmpeg", "10", "0", "10", "30"}, {"ffmpeg", "10", "0", "4", "-1"}}) {
		_, ok := parse_options(args)
		testing.expect(t, !ok)
	}
	o, ok := parse_options({"curl-reuse", "12", "0", "4", "30"})
	testing.expect(t, ok && o.seconds == 12 && o.seek_after == 4 && o.seek_to == 30)
	for mode in ([]string{"ffmpeg-stream", "ffmpeg-large", "curl", "curl-aligned", "curl-large", "curl-query", "curl-parallel"}) {
		_, accepted := parse_options({mode, "12", "0"})
		testing.expect(t, !accepted)
	}
	h3, h3_ok := parse_options({"curl-h3", "12", "0", "4", "30"})
	testing.expect(t, h3_ok && h3.mode == "curl-h3")
}
