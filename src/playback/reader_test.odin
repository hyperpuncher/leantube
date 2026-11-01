package playback

import "core:c"
import queue "core:container/queue"
import "core:testing"

@(test)
transport_diagnostics_do_not_include_private_url_parts :: proc(t: ^testing.T) {
	for row in ([]struct {
			url:  cstring,
			host: string,
		}{{"https://cdn.example.invalid/video?sig=private#private", "cdn.example.invalid"}, {"https://user:private@cdn.example.invalid/video?sig=private", ""}, {"http://127.0.0.1:1234/private?sig=private", "127.0.0.1:1234"}, {"https://[::1]/private?sig=private", "[::1]"}, {"private", ""}}) {
		host := transport_host(row.url)
		testing.expect_value(t, host, row.host)
		delete(host)
	}
}
@(test)
http_logs_reject_requests_before_formatting :: proc(t: ^testing.T) {
	testing.expect(t, safe_http_log_format(HTTP_STATISTICS))
	testing.expect(t, safe_http_log_format(HTTP_LATENCY))
	for value in ([]string{"request: %s", "header='%s'", "Opening '%s' for reading", "https://example.invalid/?sig=private", HTTP_STATISTICS + "%s"}) {
		testing.expect(t, !safe_http_log_format(value))
	}
}
@(test)
range_response_must_match_requested_bytes :: proc(t: ^testing.T) {
	first, last, total, ok := parse_range(" bytes 10-19/100\r\n")
	testing.expect(t, ok && first == 10 && last == 19 && total == 100)
	for text in ([]string{"bytes */100", "bytes -1-19/100", "bytes 20-19/100", "bytes 10-100/100", "bytes 10-x/100"}) {
		_, _, _, valid := parse_range(text)
		testing.expect(t, !valid)
	}
	h := Http {
		bytes  = make([dynamic]u8, 10),
		first  = 10,
		last   = 19,
		length = 100,
		total  = -1,
	}
	defer delete(h.bytes)
	testing.expect(t, valid_response(&h, 10, 19, 206))
	testing.expect(t, !valid_response(&h, 10, 19, 200))
	testing.expect(t, !valid_response(&h, 9, 19, 206))
	h.total = 101
	testing.expect(t, !valid_response(&h, 10, 19, 206))
	h.total = 100
	resize(&h.bytes, 9)
	testing.expect(t, !valid_response(&h, 10, 19, 206))
}
@(test)
http_body_is_bounded_and_redirect_headers_reset_response :: proc(t: ^testing.T) {
	h := Http {
		block  = 4,
		first  = 0,
		last   = 3,
		length = 20,
	}
	defer delete(h.bytes)
	bytes := [5]u8{1, 2, 3, 4, 5}
	testing.expect_value(t, http_write(raw_data(bytes[:]), 1, 4, &h), c.size_t(4))
	testing.expect_value(t, http_write(raw_data(bytes[:]), 1, 1, &h), c.size_t(0))
	testing.expect_value(t, len(h.bytes), 4)
	line := "HTTP/1.1 206 Partial Content\r\n"
	http_header(raw_data(line), 1, c.size_t(len(line)), &h)
	testing.expect(t, len(h.bytes) == 0 && h.first == -1 && h.last == -1 && h.length == -1)
}
@(test)
consuming_packets_updates_bytes_and_clearing_releases_the_tail :: proc(t: ^testing.T) {
	state := State{}
	track := Track {
		state = &state,
		eof   = true,
		end   = 2,
	}
	queue.init(&track.packets)
	defer {clear_track(&track); queue.destroy(&track.packets)}
	for end in ([]f64{1, 2}) {
		p := av_packet_alloc()
		testing.expect(t, p != nil)
		p.size = 4
		queue.push_back(&track.packets, Packet{packet = p, end = end})
		track.queued_bytes += 4
	}
	consume(&track, 1)
	testing.expect(t, queue.len(track.packets) == 1 && track.queued_bytes == 4)
	clear_track(&track)
	testing.expect(t, queue.len(track.packets) == 0 && track.queued_bytes == 0 && !track.eof)
	testing.expect_value(t, ahead(&track, 0), f64(0))
}
@(test)
custom_io_seek_handles_size_and_bounds :: proc(t: ^testing.T) {
	h := Http {
		total    = 100,
		position = 25,
	}
	testing.expect_value(t, http_seek(&h, 0, SEEK_SIZE), i64(100))
	testing.expect_value(t, http_seek(&h, 5, 1), i64(30))
	testing.expect_value(t, http_seek(&h, -10, 2), i64(90))
	testing.expect_value(t, http_seek(&h, -1, 0), i64(ERROR_ARGUMENT))
	testing.expect_value(t, http_seek(&h, 101, 0), i64(ERROR_ARGUMENT))
	testing.expect_value(t, h.position, i64(90))
}
