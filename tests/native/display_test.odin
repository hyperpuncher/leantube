package main

import "core:c"
import "core:testing"
import "core:thread"

foreign import fixture "system:AcbAPI"
foreign fixture {
	ready_callback: Acb_Callback
	metadata_calls, playing_calls, destroy_calls: c.int
	applied_metadata: [128]u8
}

@(test)
display_applies_latest_metadata_on_main_thread :: proc(t: ^testing.T) {
	defer release_display()
	testing.expect(t, attach_display("test.app", "media-id", "first"))
	poll_display()
	testing.expect_value(t, metadata_calls, 0)
	update_display("second")
	worker := thread.create_and_start(proc() {ready_callback(7, 0, 1, 1, 1, "")})
	testing.expect(t, worker != nil)
	if worker == nil {return}
	thread.destroy(worker)
	testing.expect_value(t, metadata_calls, 0)
	poll_display()
	testing.expect_value(t, string(cstring(&applied_metadata[0])), "second")
	testing.expect_value(t, playing_calls, 1)
	poll_display()
	testing.expect_value(t, metadata_calls, 1)
	release_display(); release_display()
	testing.expect_value(t, destroy_calls, 1)
}
