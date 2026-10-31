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
seek :: proc(s: ^Session, target: f64) {
	v, a := &s.tracks[0], &s.tracks[1]
	sync.mutex_lock(&v.mutex); sync.mutex_lock(&a.mutex)
	sync.atomic_store(&s.state.position, target)
	sync.atomic_store(&s.state.seek_target, target)
	for &t in s.tracks {clear_track(&t); t.end = target}
	sync.atomic_add(&s.state.generation, 1)
	for &t in s.tracks {sync.cond_broadcast(&t.changed)}
	sync.mutex_unlock(&a.mutex); sync.mutex_unlock(&v.mutex)
}
