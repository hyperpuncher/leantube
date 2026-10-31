package playback

import "base:runtime"
import "core:c"
import queue "core:container/queue"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import curl "vendor:curl"

STARTUP_SECONDS :: 3.0
MAXIMUM_SECONDS :: 20.0
Options :: struct {
	mode:                 string,
	receive_buffer_bytes: c.int,
	decoder_preroll:      bool,
	trace:                bool,
	start:                f64,
}
State :: struct {
	stopped:               bool,
	failure:               c.int,
	generation:            u32,
	position, seek_target: f64,
}
Packet :: struct {
	packet: ^AVPacket,
	end:    f64,
	pts:    f64,
}
Track :: struct {
	state:                                                         ^State,
	options:                                                       Options,
	url:                                                           string,
	media_type:                                                    c.int,
	mutex:                                                         sync.Mutex,
	changed:                                                       sync.Cond,
	packets:                                                       queue.Queue(Packet),
	eof:                                                           bool,
	queued_bytes, read_bytes, io_bytes, discarded:                 i64,
	end:                                                           f64,
	width, height:                                                 c.int,
	frame_rate:                                                    Rational,
	color_transfer:                                                c.int,
	audio_config:                                                  [2]u8,
	audio_config_valid:                                            bool,
	fps, open_s, info_s, seek_s, first_packet_s, first_pts:        f64,
	hot_seek_s, hot_first_pts:                                     f64,
	http_statistics:                                               [dynamic]string,
	curl_protocol, curl_transfers, curl_connections, curl_retries: c.long,
}
@(thread_local)
log_track: ^Track
HTTP_STATISTICS :: "Statistics: %d connection%s, %d request%s, %d retr%s, %d reconnection%s, %d redirect%s\n"
HTTP_LATENCY :: "Latency: %.2f ms avg, %.2f ms max\n"
safe_http_log_format :: proc(value: string) -> bool {return(
		value == HTTP_STATISTICS ||
		value == HTTP_LATENCY \
	)}
http_statistics_log :: proc "c" (_: rawptr, level: c.int, format: cstring, args: rawptr) {
	context = runtime.default_context()
	// Reject URL-bearing messages before formatting. Passing nil also omits
	// the FFmpeg context prefix, which could contain an input name.
	if log_track == nil || format == nil || !safe_http_log_format(string(format)) {return}
	buffer: [256]u8
	prefix: c.int
	n := av_log_format_line2(
		nil,
		level,
		format,
		args,
		raw_data(buffer[:]),
		c.int(len(buffer)),
		&prefix,
	)
	if n > 0 &&
	   n <
		   c.int(
			   len(buffer),
		   ) {append(&log_track.http_statistics, strings.clone(strings.trim_space(string(buffer[:n]))))}
}
seconds_since :: proc(start: time.Tick) -> f64 {return time.duration_seconds(
		time.tick_since(start),
	)}
rational_seconds :: proc(value: Rational) -> f64 {return f64(value.num) / f64(value.den)}
clear_track :: proc(t: ^Track) {
	for queue.len(t.packets) > 0 {
		p := queue.pop_front(&t.packets)
		av_packet_free(&p.packet)
	}
	t.queued_bytes = 0
	t.eof = false
}
ahead :: proc(t: ^Track, clock: f64) -> f64 {
	return queue.len(t.packets) == 0 ? 0 : max(0, t.end - clock)
}
consume :: proc(t: ^Track, clock: f64) {
	for queue.len(t.packets) > 0 && queue.front(&t.packets).end <= clock {
		p := queue.pop_front(&t.packets)
		t.queued_bytes -= i64(p.packet.size)
		av_packet_free(&p.packet)
	}
	sync.cond_signal(&t.changed)
}
read_track :: proc(worker: ^thread.Thread) {
	t := cast(^Track)worker.data
	log_track = t
	defer {log_track = nil}
	s := t.state
	begun, stage := time.tick_now(), time.tick_now()
	format := avformat_alloc_context()
	if format == nil {sync.atomic_store(&s.failure, ERROR_MEMORY); return}
	io: ^AVIOContext
	h := Http {
		cancel = {state = s},
		handle = curl.easy_init(),
		url = strings.clone(t.url),
		mode = t.options.mode,
		receive_buffer_request = t.options.receive_buffer_bytes,
		trace = t.options.trace,
		label = t.media_type == 0 ? "video" : "audio",
		begun = begun,
		block = BLOCK_BYTES,
		total = -1,
	}
	defer http_close(&h)
	format.interrupt_callback = {interrupt, &h.cancel}
	options: ^AVDictionary
	result := c.int(0)
	for pair in ([][2]cstring{{"request_size", "1048576"}, {"initial_request_size", "1048576"}, {"multiple_requests", "1"}, {"icy", "0"}, {"rw_timeout", "15000000"}, {"tls_verify", "1"}, {"ca_file", "/etc/ssl/certs/ca-certificates.crt"}, {"user_agent", "leantube"}}) {
		result = av_dict_set(&options, pair[0], pair[1], 0)
		if result < 0 {break}
	}
	if result >= 0 && h.mode != "ffmpeg" {
		if !http_fetch(&h, 0) {result = ERROR_IO} else {
			buffer := av_malloc(32768)
			if buffer == nil {result = ERROR_MEMORY} else {
				io = avio_alloc_context(buffer, 32768, 0, &h, http_read, nil, http_seek)
				if io == nil {av_freep(&buffer); result = ERROR_MEMORY} else {
					io.seekable = 1
					format.pb = io
					format.flags |= 0x80 // AVFMT_FLAG_CUSTOM_IO
				}
			}
		}
	}
	url := strings.clone_to_cstring(t.url)
	defer delete(url)
	if result >= 0 {result = avformat_open_input(&format, url, nil, &options)}
	av_dict_free(&options)
	t.open_s = seconds_since(stage)
	stage = time.tick_now()
	if result >= 0 {result = avformat_find_stream_info(format, nil)}
	t.info_s = seconds_since(stage)
	stage = time.tick_now()
	index := c.int(-1)
	if result >= 0 {
		index = av_find_best_stream(format, t.media_type, -1, -1, nil, 0)
		if index < 0 {result = index}
	}
	mux: ^AVFormatContext
	if result >= 0 && t.options.decoder_preroll {
		parameters := format.streams[index].codecpar
		if string(avcodec_get_name(parameters.codec_id)) !=
		   (t.media_type == 0 ? "vp9" : "aac") {result = ERROR_INVALID_DATA}
		if result >= 0 && t.media_type == 1 {
			mux = aac_muxer(parameters)
			if mux == nil {result = ERROR_INVALID_DATA}
		}
	}
	defer if mux != nil {avformat_free_context(mux)}
	start := t.options.start
	if result >= 0 && start > 0 {result = av_seek_frame(format, -1, i64(start * 1e6), 1)}
	t.seek_s = seconds_since(stage)
	if result >= 0 {
		stream := format.streams[index]
		sync.mutex_lock(&t.mutex)
		t.width, t.height = stream.codecpar.width, stream.codecpar.height
		t.frame_rate = av_guess_frame_rate(format, stream, nil)
		t.fps = rational_seconds(t.frame_rate)
		t.color_transfer = stream.codecpar.color_trc
		if t.media_type == 1 && stream.codecpar.extradata_size >= 2 {
			copy(t.audio_config[:], (cast([^]u8)stream.codecpar.extradata)[:2])
			t.audio_config_valid = true
		}
		sync.mutex_unlock(&t.mutex)
	}
	for result >= 0 && !sync.atomic_load(&s.stopped) {
		if h.cancel.generation != sync.atomic_load(&s.generation) {
			h.cancel.generation = sync.atomic_load(&s.generation)
			start = sync.atomic_load(&s.seek_target)
			at := time.tick_now()
			result = av_seek_frame(format, -1, i64(start * 1e6), 1)
			t.hot_seek_s = seconds_since(at)
			if result < 0 {break}
		}
		p := av_packet_alloc()
		if p == nil {result = ERROR_MEMORY; break}
		result = av_read_frame(format, p)
		if result < 0 {
			av_packet_free(&p)
			if h.cancel.generation != sync.atomic_load(&s.generation) {result = 0; continue}
			if result == ERROR_EOF {
				sync.mutex_lock(&t.mutex)
				if h.cancel.generation == sync.atomic_load(&s.generation) {
					if h.cancel.generation > 0 &&
					   t.end <= start &&
					   format.duration != NO_PTS &&
					   start + 0.1 < f64(format.duration) / 1e6 {
						result = ERROR_INVALID_DATA
					} else {
						t.eof = true
						for !cancelled(&h.cancel) {sync.cond_wait(&t.changed, &t.mutex)}
						result = 0
					}
				} else {result = 0}
				sync.mutex_unlock(&t.mutex)
				continue
			}
			break
		}
		if p.stream_index != index || p.pts == NO_PTS {av_packet_free(&p); continue}
		base := rational_seconds(format.streams[index].time_base)
		end := f64(p.pts + p.duration) * base
		if t.first_packet_s <
		   0 {t.first_packet_s = seconds_since(begun); t.first_pts = f64(p.pts) * base}
		if h.cancel.generation > 0 && t.hot_first_pts < 0 {t.hot_first_pts = f64(p.pts) * base}
		if end <= start &&
		   !(t.options.decoder_preroll &&
				   t.media_type == 0) {t.discarded += 1; av_packet_free(&p); continue}
		if mux != nil &&
		   !aac_frame(mux, &p) {av_packet_free(&p); result = ERROR_INVALID_DATA; break}
		sync.mutex_lock(&t.mutex)
		for !cancelled(&h.cancel) &&
		    (end - sync.atomic_load(&s.position) > MAXIMUM_SECONDS ||
				    (queue.len(t.packets) > 0 &&
						    end - queue.front(&t.packets).pts >
							    MAXIMUM_SECONDS)) {sync.cond_wait(&t.changed, &t.mutex)}
		if cancelled(&h.cancel) {av_packet_free(&p)} else {
			if ok, _ := queue.push_back(&t.packets, Packet{p, end, f64(p.pts) * base});
			   !ok {av_packet_free(&p); result = ERROR_MEMORY} else {
				t.read_bytes += i64(p.size)
				t.queued_bytes += i64(p.size)
				t.end = end
			}
		}
		sync.mutex_unlock(&t.mutex)
	}
	if result < 0 &&
	   result != ERROR_EOF &&
	   !sync.atomic_load(&s.stopped) {sync.atomic_store(&s.failure, result)}
	sync.mutex_lock(&t.mutex)
	t.eof = true
	sync.mutex_unlock(&t.mutex)
	if format != nil && format.pb != nil {t.io_bytes = format.pb.bytes_read}
	avformat_close_input(&format)
	t.curl_protocol, t.curl_transfers, t.curl_connections, t.curl_retries =
		h.protocol, h.transfers, h.connections, h.retries
	if io != nil {av_freep(&io.buffer); avio_context_free(&io)}
}
