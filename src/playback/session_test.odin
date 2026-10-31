package playback

import "core:c"
import queue "core:container/queue"
import "core:fmt"
import "core:sync"
import "core:testing"
import "core:time"
import curl "vendor:curl"

@(test)
session_bounds_both_queues_seeks_and_joins_workers :: proc(t: ^testing.T) {
	testing.expect(t, HTTP_TEST_SERVER != "")
	if HTTP_TEST_SERVER == "" {return}
	testing.expect_value(t, curl.global_init(c.long(curl.GLOBAL_DEFAULT)), curl.code.E_OK)
	defer curl.global_cleanup()
	video := fmt.aprintf("%s/video", HTTP_TEST_SERVER)
	audio := fmt.aprintf("%s/audio", HTTP_TEST_SERVER)
	s := open(video, audio, {mode = "curl-reuse", decoder_preroll = true})
	// The caller can release the source URLs as soon as open returns.
	delete(video); delete(audio)
	testing.expect(t, s != nil)
	if s == nil {return}
	defer close(s)
	v, a := &s.tracks[0], &s.tracks[1]
	full := false
	begun := time.tick_now()
	for seconds_since(begun) < 5 && sync.atomic_load(&s.state.failure) == 0 {
		sync.mutex_lock(&v.mutex); sync.mutex_lock(&a.mutex)
		full = v.end >= 19.8 && a.end >= 19.8
		for &track in s.tracks {
			testing.expect(t, track.end <= MAXIMUM_SECONDS)
			if queue.len(track.packets) > 0 {
				testing.expect(t, track.end - queue.front(&track.packets).pts <= MAXIMUM_SECONDS)
			}
		}
		sync.mutex_unlock(&a.mutex); sync.mutex_unlock(&v.mutex)
		if full {break}
		time.sleep(time.Millisecond)
	}
	testing.expect_value(t, sync.atomic_load(&s.state.failure), c.int(0))
	testing.expect(t, full)
	if !full {return}
	seek(s, 21)
	testing.expect_value(t, sync.atomic_load(&s.state.generation), u32(1))
	ended := false
	begun = time.tick_now()
	for seconds_since(begun) < 5 && sync.atomic_load(&s.state.failure) == 0 {
		sync.mutex_lock(&v.mutex); sync.mutex_lock(&a.mutex)
		ended = v.eof && a.eof
		sync.mutex_unlock(&a.mutex); sync.mutex_unlock(&v.mutex)
		if ended {break}
		time.sleep(time.Millisecond)
	}
	testing.expect(t, ended)
	stop(s)
	testing.expect_value(t, sync.atomic_load(&s.state.failure), c.int(0))
	testing.expect(t, s.workers[0] == nil && s.workers[1] == nil)
	testing.expect(t, v.width == 32 && v.height == 32 && v.fps == 5)
	testing.expect(t, queue.len(v.packets) > 0 && queue.len(a.packets) > 0)
	testing.expect(t, v.hot_first_pts >= 20 && v.hot_first_pts <= 21)
	testing.expect(t, a.hot_first_pts >= 20 && a.hot_first_pts <= 21.1)
}
