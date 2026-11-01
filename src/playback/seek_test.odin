package playback

import "core:c"
import queue "core:container/queue"
import "core:fmt"
import "core:sync"
import "core:testing"
import curl "vendor:curl"

@(test)
seeks_during_input_open_apply_only_the_latest_target :: proc(t: ^testing.T) {
	testing.expect_value(t, curl.global_init(c.long(curl.GLOBAL_DEFAULT)), curl.code.E_OK)
	defer curl.global_cleanup()
	video, audio :=
		fmt.aprintf("%s/video", HTTP_TEST_SERVER), fmt.aprintf("%s/audio", HTTP_TEST_SERVER)
	s := open(video, audio, {mode = "curl-reuse", decoder_preroll = true})
	delete(video); delete(audio)
	if !testing.expect(t, s != nil) {return}
	defer close(s)
	// Input opening is still in progress. These requests must not abort it.
	seek(s, 10)
	seek(s, 20)
	seek(s, 41)
	if !testing.expect(t, wait_for_tracks(s, eof = true)) {return}
	stop(s)
	testing.expect_value(t, sync.atomic_load(&s.state.failure), c.int(0))
	testing.expect_value(t, sync.atomic_load(&s.state.seek_target), f64(41))
	for &track in s.tracks {
		testing.expect(t, queue.len(track.packets) > 0)
		for index in 0 ..< queue.len(track.packets) {
			p := queue.get(&track.packets, index)
			testing.expect_value(t, p.generation, u32(3))
			testing.expect(t, p.pts >= 40)
		}
	}
}
