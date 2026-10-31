package diagnostics

import reader "../../../src/playback"
import "core:c"
import queue "core:container/queue"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:time"
import curl "vendor:curl"

Options :: struct {
	using reader:        reader.Options,
	seconds:             int,
	seek_after, seek_to: f64,
}

receive_buffer_setting :: proc() -> (value: c.int, ok: bool) {
	text := os.get_env("LEANTUBE_READER_RCVBUF", context.allocator)
	defer delete(text)
	if text == "" {return 0, true}
	n, parsed := strconv.parse_int(text)
	return c.int(n), parsed && n >= 0 && n <= 8 * 1024 * 1024
}
peak_rss_kib :: proc() -> i64 {
	// Avoid the different time32/time64 getrusage layouts on ARM32 libc.
	data, error := os.read_entire_file("/proc/self/status", context.allocator)
	if error != nil {return -1}
	defer delete(data)
	lines := strings.split(string(data), "\n")
	defer delete(lines)
	for line in lines {
		if !strings.has_prefix(line, "VmHWM:") {continue}
		value := strings.trim_space(strings.trim_suffix(line[6:], "kB"))
		if rss, ok := strconv.parse_i64(value, 10); ok {return rss}
	}
	return -1
}
parse_options :: proc(args: []string) -> (o: Options, ok: bool) {
	if len(args) != 3 && len(args) != 5 {return}
	o.mode, o.seek_after = args[0], -1
	o.trace = true
	switch o.mode {case "ffmpeg", "curl-reuse", "curl-h3":; case:
		return}
	seconds, seconds_ok := strconv.parse_int(args[1])
	start, start_ok := strconv.parse_f64(args[2])
	if !seconds_ok || !start_ok {return}
	o.seconds, o.start = seconds, start
	if len(args) == 5 {
		after, after_ok := strconv.parse_f64(args[3])
		target, target_ok := strconv.parse_f64(args[4])
		if !after_ok || !target_ok {return}
		o.seek_after, o.seek_to = after, target
	}
	for value in ([]f64{o.start, o.seek_after, o.seek_to}) {if math.is_nan(value) || math.is_inf(value) {return}}
	ok =
		o.seconds >= 1 &&
		o.start >= 0 &&
		(o.seek_after < 0 || (o.seek_after < f64(o.seconds) && o.seek_to >= 0))
	return
}
entry :: proc(args: []string) -> int {
	o, ok := parse_options(args)
	if !ok {fmt.eprintln("expected MODE SECONDS START [SEEK_AFTER SEEK_TO]"); return 2}
	o.receive_buffer_bytes, ok = receive_buffer_setting()
	if !ok || (o.receive_buffer_bytes > 0 && o.mode == "ffmpeg") {return 2}
	data, error := os.read_entire_file(os.stdin, context.allocator)
	if error != nil {return 2}
	defer delete(data)
	lines := strings.split(string(data), "\n")
	defer delete(lines)
	if len(lines) < 2 {return 2}
	for url in lines[:2] {if !strings.has_prefix(url, "https://") && !strings.has_prefix(url, "http://") {return 2}}
	return run(o, lines[0], lines[1])
}
run :: proc(o: Options, video_url, audio_url: string) -> int {
	fmt.printf(
		"{{\"ffmpeg_version\":\"%s\",\"curl_version\":\"%s\"}}\n",
		reader.av_version_info(),
		curl.version(),
	)
	if curl.global_init(c.long(curl.GLOBAL_DEFAULT)) != .E_OK {return 3}
	defer curl.global_cleanup()
	session := reader.open(video_url, audio_url, o.reader)
	if session == nil {return 3}
	defer reader.close(session)
	s := &session.state
	video, audio := &session.tracks[0], &session.tracks[1]
	begun := time.tick_now()
	previous := begun
	playing, started, ended, seek_issued, seek_waiting := false, false, false, false, false
	stalls := 0
	clock, startup_seconds, rebuffer_seconds, next_report := o.start, f64(-1), f64(0), f64(0)
	max_video, max_audio, played, seek_at_wall, seek_ready :=
		f64(0), f64(0), f64(0), f64(0), f64(-1)
	for sync.atomic_load(&s.failure) == 0 {
		now := time.tick_now()
		dt := time.duration_seconds(time.tick_diff(previous, now))
		previous = now
		wall := reader.seconds_since(begun)
		sync.mutex_lock(&video.mutex); sync.mutex_lock(&audio.mutex)
		if !seek_issued && o.seek_after >= 0 && played >= o.seek_after {
			seek_issued, seek_waiting, playing = true, true, false
			seek_at_wall, clock = wall, o.seek_to
			sync.mutex_unlock(&audio.mutex); sync.mutex_unlock(&video.mutex)
			reader.seek(session, clock)
			sync.mutex_lock(&video.mutex); sync.mutex_lock(&audio.mutex)
			fmt.printf(
				"{{\"event\":\"seek_requested\",\"wall_s\":%.3f,\"target_s\":%.3f}}\n",
				wall,
				clock,
			)
		}
		if playing {
			next := min(clock + dt, min(video.end, audio.end))
			played += next - clock
			clock = next
			sync.atomic_store(&s.position, clock)
			reader.consume(video, clock); reader.consume(audio, clock)
			if queue.len(video.packets) == 0 || queue.len(audio.packets) == 0 {
				playing = false
				if !((video.eof && queue.len(video.packets) == 0) ||
					   (audio.eof && queue.len(audio.packets) == 0)) {stalls += 1}
			}
		} else {
			if started && !seek_waiting {rebuffer_seconds += dt}
			if (reader.ahead(video, clock) >= reader.STARTUP_SECONDS || video.eof) &&
			   (reader.ahead(audio, clock) >= reader.STARTUP_SECONDS || audio.eof) {
				playing = true
				if !started {startup_seconds = wall}
				started = true
				if seek_waiting {seek_ready = wall - seek_at_wall; seek_waiting = false}
			}
		}
		max_video, max_audio =
			max(max_video, reader.ahead(video, clock)), max(max_audio, reader.ahead(audio, clock))
		if wall >= next_report {
			fmt.printf(
				"{{\"wall_s\":%.3f,\"position_s\":%.3f,\"video_buffer_s\":%.3f,\"audio_buffer_s\":%.3f,\"video_queue_bytes\":%d,\"audio_queue_bytes\":%d,\"playing\":%s}}\n",
				wall,
				clock,
				reader.ahead(video, clock),
				reader.ahead(audio, clock),
				video.queued_bytes,
				audio.queued_bytes,
				playing ? "true" : "false",
			)
			next_report = wall + 1
		}
		ended =
			(video.eof && queue.len(video.packets) == 0) ||
			(audio.eof && queue.len(audio.packets) == 0)
		sync.mutex_unlock(&audio.mutex); sync.mutex_unlock(&video.mutex)
		if played >= f64(o.seconds) || wall >= f64(o.seconds) + 90 || ended {break}
		time.sleep(10 * time.Millisecond)
	}
	reader.stop(session)
	for t, i in ([]^reader.Track{video, audio}) {
		name := i == 0 ? "video" : "audio"
		if t.curl_transfers >
		   0 {fmt.printf("{{\"curl_reader\":\"%s\",\"protocol\":%d,\"transfers\":%d,\"connections\":%d,\"receive_retries\":%d}}\n", name, t.curl_protocol, t.curl_transfers, t.curl_connections, t.curl_retries)}
		for line in t.http_statistics {fmt.printf("{{\"http_reader\":\"%s\",\"statistics\":\"%s\"}}\n", name, line)}
		fmt.printf(
			"{{\"reader\":\"%s\",\"open_s\":%.3f,\"info_s\":%.3f,\"seek_s\":%.3f,\"first_packet_s\":%.3f,\"first_pts\":%.3f,\"discarded_packets\":%d,\"io_bytes\":%d}}\n",
			name,
			t.open_s,
			t.info_s,
			t.seek_s,
			t.first_packet_s,
			t.first_pts,
			t.discarded,
			t.io_bytes,
		)
		if seek_issued {fmt.printf("{{\"seek_track\":\"%s\",\"call_s\":%.3f,\"first_pts\":%.3f}}\n", name, t.hot_seek_s, t.hot_first_pts)}
	}
	failure := sync.atomic_load(&s.failure)
	fmt.printf(
		"{{\"summary\":true,\"mode\":\"%s\",\"width\":%d,\"height\":%d,\"fps\":%.3f,\"startup_s\":%.3f,\"played_s\":%.3f,\"rebuffer_s\":%.3f,\"stalls\":%d,\"max_video_buffer_s\":%.3f,\"max_audio_buffer_s\":%.3f,\"max_rss_kib\":%d,\"seek_ready_s\":%.3f,\"error\":%d}}\n",
		o.mode,
		video.width,
		video.height,
		video.fps,
		startup_seconds,
		played,
		rebuffer_seconds,
		stalls,
		max_video,
		max_audio,
		peak_rss_kib(),
		seek_ready,
		failure,
	)
	fmt.printf("{{\"end_of_stream\":%s}}\n", ended ? "true" : "false")
	return(
		failure != 0 || (played < f64(o.seconds) && !ended) || (o.seek_after >= 0 && seek_ready < 0) ? 1 : 0 \
	)
}
