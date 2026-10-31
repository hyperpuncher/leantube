package main

import reader "../tests/playback/diagnostics"
import "core:os"

PLAYBACK_BENCH :: #config(PLAYBACK_BENCH, false)

benchmark_reader_entry :: proc() {
	when PLAYBACK_BENCH {
		if len(os.args) < 2 {return}
		if os.args[1] == "--transport-bench" {os.exit(reader.transport_entry(os.args[2:]))}
		if os.args[1] == "--decoder-bench" {os.exit(decoder_entry(os.args[2:]))}
		if os.args[1] == "--reader-bench" {os.exit(reader.entry(os.args[2:]))}
	}
}
