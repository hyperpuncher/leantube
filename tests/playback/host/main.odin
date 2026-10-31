package main

import reader "../diagnostics"
import "core:os"

main :: proc() {
	if len(os.args) > 1 &&
	   os.args[1] == "--transport-bench" {os.exit(reader.transport_entry(os.args[2:]))}
	os.exit(reader.entry(os.args[1:]))
}
