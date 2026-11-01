package playback

import "core:c"
import queue "core:container/queue"
import "core:strings"
import "core:sync"
import "core:thread"

// A session owns its URLs, workers, and packet queues. Do not copy it.
Session :: struct {
	state:   State,
	tracks:  [2]Track,
	workers: [2]^thread.Thread,
}

open :: proc(video_url, audio_url: string, options: Options) -> ^Session {
	if avformat_version() >> 16 != 63 ||
	   avcodec_version() >> 16 != 63 ||
	   avutil_version() >> 16 != 61 {return nil}
	// Set the safe callback before a worker can open a signed media URL.
	av_log_set_callback(http_statistics_log)
	av_log_set_level(options.trace ? 48 : -8)
	s := new(Session)
	s.state.position, s.state.seek_target = options.start, options.start
	s.state.read_end = options.end
	for url, i in ([2]string{video_url, audio_url}) {
		t := &s.tracks[i]
		t^ = Track {
			state          = &s.state,
			options        = options,
			url            = strings.clone(url),
			media_type     = c.int(i),
			first_packet_s = -1,
			first_pts      = -1,
			hot_first_pts  = -1,
		}
		if queue.init(&t.packets) != nil {close(s); return nil}
		s.workers[i] = thread.create(read_track)
		if s.workers[i] == nil {close(s); return nil}
		s.workers[i].data = t
		thread.start(s.workers[i])
	}
	return s
}

// Join workers before reading their final statistics or freeing track storage.
stop :: proc(s: ^Session) {
	sync.atomic_store(&s.state.stopped, true)
	for &t in s.tracks {
		sync.mutex_lock(&t.mutex)
		sync.cond_broadcast(&t.changed)
		sync.mutex_unlock(&t.mutex)
	}
	for &worker in s.workers {
		if worker != nil {thread.destroy(worker); worker = nil}
	}
}

close :: proc(s: ^Session) {
	if s == nil {return}
	stop(s)
	for &t in s.tracks {
		clear_track(&t)
		queue.destroy(&t.packets)
		delete(t.url)
		for line in t.http_statistics {delete(line)}
		delete(t.http_statistics)
	}
	free(s)
}

// Call from the consumer thread, without holding either track mutex.
seek :: proc(s: ^Session, target: f64, end: f64 = 0) {
	v, a := &s.tracks[0], &s.tracks[1]
	sync.mutex_lock(&v.mutex); sync.mutex_lock(&a.mutex)
	sync.atomic_store(&s.state.position, target)
	if s.state.skip_end > s.state.skip_start &&
	   (target == s.state.skip_end || (target > s.state.skip_end && target <= min(v.end, a.end))) {
		// The workers already sought. Keep their packets and codec pre-roll.
		s.state.consumer_generation = sync.atomic_load(&s.state.generation)
		for &t in s.tracks {
			for queue.len(t.packets) > 0 && !current_packet(&t) {
				p := queue.pop_front(&t.packets)
				t.queued_bytes -= i64(p.packet.size)
				av_packet_free(&p.packet)
			}
		}
	} else {
		sync.atomic_store(&s.state.seek_target, target)
		s.state.read_end = end
		for &t in s.tracks {clear_track(&t); t.end = target}
		sync.atomic_add(&s.state.generation, 1)
		s.state.consumer_generation = sync.atomic_load(&s.state.generation)
	}
	s.state.skip_start, s.state.skip_end = 0, 0
	for &t in s.tracks {sync.cond_broadcast(&t.changed)}
	sync.mutex_unlock(&a.mutex); sync.mutex_unlock(&v.mutex)
}

// Retain the current span, then fill the same queues after the jump.
// end is the next sponsor boundary, or zero for the rest of the source.
prepare_skip :: proc(s: ^Session, from, to, end: f64) -> bool {
	v, a := &s.tracks[0], &s.tracks[1]
	sync.mutex_lock(&v.mutex); sync.mutex_lock(&a.mutex)
	defer {sync.mutex_unlock(&a.mutex); sync.mutex_unlock(&v.mutex)}
	if s.state.skip_end > s.state.skip_start || from < 0 || to <= from {return false}
	for &t in s.tracks {
		if t.end <= 0 || (t.end < from && !t.at_limit) {return false}
	}
	for &t in s.tracks {
		for queue.len(t.packets) > 0 && queue.back(&t.packets).decode_time >= from {
			p := queue.pop_back(&t.packets)
			t.queued_bytes -= i64(p.packet.size)
			av_packet_free(&p.packet)
		}
		t.end = queue.len(t.packets) > 0 ? queue.back(&t.packets).end : min(t.end, from)
		t.skip_boundary = t.end
		t.eof, t.at_limit = false, false
	}
	s.state.skip_start, s.state.skip_end, s.state.read_end = from, to, end
	sync.atomic_store(&s.state.seek_target, to)
	sync.atomic_add(&s.state.generation, 1)
	for &t in s.tracks {sync.cond_broadcast(&t.changed)}
	return true
}
