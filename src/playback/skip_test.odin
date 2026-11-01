package playback

import "core:c"
import queue "core:container/queue"
import "core:fmt"
import "core:sync"
import "core:testing"
import "core:time"
import curl "vendor:curl"

wait_for_tracks :: proc(s: ^Session, end: f64 = 0, eof: bool = false) -> bool {
	begun := time.tick_now()
	for seconds_since(begun) < 5 && sync.atomic_load(&s.state.failure) == 0 {
		v, a := &s.tracks[0], &s.tracks[1]
		sync.mutex_lock(&v.mutex); sync.mutex_lock(&a.mutex)
		ready := v.end >= end && a.end >= end && (!eof || (v.eof && a.eof))
		sync.mutex_unlock(&a.mutex); sync.mutex_unlock(&v.mutex)
		if ready {return true}
		time.sleep(time.Millisecond)
	}
	return false
}

@(test)
prepared_skip_keeps_both_spans_bounded_and_reuses_packets_and_workers :: proc(t: ^testing.T) {
	testing.expect_value(t, curl.global_init(c.long(curl.GLOBAL_DEFAULT)), curl.code.E_OK)
	defer curl.global_cleanup()
	for target in ([]f64{11.6, 4.3}) {
		video, audio :=
			fmt.aprintf("%s/video", HTTP_TEST_SERVER), fmt.aprintf("%s/audio", HTTP_TEST_SERVER)
		s := open(video, audio, {mode = "curl-reuse", decoder_preroll = true, end = 4.1})
		delete(video); delete(audio)
		if !testing.expect(t, s != nil) {return}
		defer close(s)
		workers := s.workers
		if !testing.expect(t, wait_for_tracks(s, eof = true)) {return}
		if !testing.expect(t, prepare_skip(s, 4.1, target, target + 19.5)) {return}
		// A long source-time gap must not stop the reader at source time 20.
		if !testing.expect(t, wait_for_tracks(s, target > 10 ? 26 : 19)) {return}
		first: [2]^AVPacket
		for &track, i in s.tracks {
			sync.mutex_lock(&track.mutex)
			// Measure actual packet spans independently of the reader's gap offset.
			starts := [2]f64{1e9, 1e9}
			ends: [2]f64
			for index in 0 ..< queue.len(track.packets) {
				p := queue.get(&track.packets, index)
				testing.expect(t, p.generation <= 1)
				starts[p.generation] = min(starts[p.generation], p.pts)
				ends[p.generation] = max(ends[p.generation], p.end)
				if p.generation == 0 {testing.expect(t, p.decode_time < 4.1)} else {
					testing.expect(t, p.decode_time < target + 19.5)
					if first[i] == nil {first[i] = p.packet}
				}
			}
			testing.expect(t, starts[0] < 4.1 && starts[1] <= target)
			testing.expect(t, ends[1] >= (target > 10 ? 26 : 19))
			testing.expect(t, ends[0] - starts[0] + ends[1] - starts[1] <= 20.000001)
			consume(&track, 5)
			testing.expect(t, span_drained(&track))
			testing.expect(t, !current_packet(&track) && queue.len(track.packets) > 0)
			testing.expect_value(t, queue.front(&track.packets).packet, first[i])
			sync.mutex_unlock(&track.mutex)
		}
		seek(s, target)
		testing.expect_value(t, sync.atomic_load(&s.state.generation), u32(1))
		testing.expect_value(t, s.state.consumer_generation, u32(1))
		testing.expect_value(t, s.workers, workers)
		for &track, i in s.tracks {
			sync.mutex_lock(&track.mutex)
			testing.expect_value(t, queue.front(&track.packets).packet, first[i])
			testing.expect(t, current_packet(&track) && ahead(&track, target) >= 3)
			consume(&track, target + 2.4)
			sync.mutex_unlock(&track.mutex)
		}
		sync.atomic_store(&s.state.position, target + 2.4)
		// The prepared span stops before the following sponsor section.
		if !testing.expect(t, wait_for_tracks(s, eof = true)) {return}
		for &track in s.tracks {
			sync.mutex_lock(&track.mutex)
			testing.expect(t, track.at_limit)
			testing.expect(t, queue.back(&track.packets).decode_time < target + 19.5)
			sync.mutex_unlock(&track.mutex)
		}
		testing.expect(t, prepare_skip(s, target + 19.5, target + 23.1, 0))
		// An unrelated manual seek must cancel the prepared span on both tracks.
		seek(s, 1, 4.1)
		if !testing.expect(t, wait_for_tracks(s, eof = true)) {return}
		stop(s)
		testing.expect_value(t, sync.atomic_load(&s.state.failure), c.int(0))
		testing.expect(t, s.workers[0] == nil && s.workers[1] == nil)
		testing.expect_value(t, s.state.skip_end, f64(0))
		for &track in s.tracks {
			for index in 0 ..< queue.len(track.packets) {
				p := queue.get(&track.packets, index)
				testing.expect_value(t, p.generation, s.state.consumer_generation)
				testing.expect(t, p.decode_time < 4.1)
			}
		}
	}
}
