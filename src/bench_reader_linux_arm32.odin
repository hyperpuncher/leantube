package main

import reader "../tests/playback/diagnostics"
import "core:os"

PLAYBACK_BENCH :: #config(PLAYBACK_BENCH, false)

// A constant condition keeps the benchmark type-checked in every build.
// Release builds compile it out.
benchmark_reader_entry :: proc() {
	if !PLAYBACK_BENCH || len(os.args) < 2 {return}
	switch os.args[1] {
	case "--transport-bench":
		os.exit(reader.transport_entry(os.args[2:]))
	case "--decoder-bench":
		os.exit(decoder_entry(os.args[2:]))
	case "--reader-bench":
		os.exit(reader.entry(os.args[2:]))
	}
}
