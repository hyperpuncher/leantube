package playback

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:sys/posix"
import "core:time"
import curl "vendor:curl"

BLOCK_BYTES :: 1024 * 1024
Cancel :: struct {
	state:      ^State,
	generation: u32,
	opening:    bool,
}
Http :: struct {
	cancel:                                        Cancel,
	handle:                                        ^curl.CURL,
	url:                                           string,
	mode:                                          string,
	trace:                                         bool,
	label:                                         string,
	begun:                                         time.Tick,
	block:                                         int,
	bytes:                                         [dynamic]u8,
	position, base, total, first, last, length:    i64,
	protocol, transfers, connections, retries:     c.long,
	redirect_status:                               c.long,
	receive_buffer_request, receive_buffer_actual: c.int,
}
http_socket_options :: proc "c" (
	arg: rawptr,
	socket: curl.socket_t,
	purpose: curl.socktype,
) -> c.int {
	if purpose != .IPCXN {return curl.SOCKOPT_OK}
	h := cast(^Http)arg
	length := posix.socklen_t(size_of(c.int))
	if h.receive_buffer_request > 0 &&
	   posix.setsockopt(
		   posix.FD(socket),
		   posix.SOL_SOCKET,
		   .RCVBUF,
		   &h.receive_buffer_request,
		   length,
	   ) !=
		   .OK {return curl.SOCKOPT_ERROR}
	if posix.getsockopt(
		   posix.FD(socket),
		   posix.SOL_SOCKET,
		   .RCVBUF,
		   &h.receive_buffer_actual,
		   &length,
	   ) !=
	   .OK {return curl.SOCKOPT_ERROR}
	return curl.SOCKOPT_OK
}
cancelled :: proc "contextless" (cancel: ^Cancel) -> bool {
	return(
		sync.atomic_load(&cancel.state.stopped) ||
		(!cancel.opening && cancel.generation != sync.atomic_load(&cancel.state.generation)) \
	)
}
interrupt :: proc "c" (arg: rawptr) -> c.int {
	return c.int(cancelled(cast(^Cancel)arg))
}
http_write :: proc "c" (data: rawptr, size, count: c.size_t, arg: rawptr) -> c.size_t {
	context = runtime.default_context()
	h := cast(^Http)arg
	if size != 0 && count > c.size_t(h.block) / size {return 0}
	n := int(size * count)
	if n > h.block - len(h.bytes) {return 0}
	written, error := append(&h.bytes, ..(cast([^]u8)data)[:n])
	return error == nil ? c.size_t(written) : 0
}
// A range response must identify every returned byte. Redirect headers reset
// the previous response so only the final response can satisfy validation.
parse_range :: proc(line: string) -> (first, last, total: i64, ok: bool) {
	text := strings.trim_space(line)
	if !strings.has_prefix(text, "bytes ") {return -1, -1, -1, false}
	text = text[6:]
	dash, slash := strings.index_byte(text, '-'), strings.index_byte(text, '/')
	if dash <= 0 || slash <= dash + 1 {return -1, -1, -1, false}
	a, a_ok := strconv.parse_i64(text[:dash], 10)
	b, b_ok := strconv.parse_i64(text[dash + 1:slash], 10)
	c, c_ok := strconv.parse_i64(text[slash + 1:], 10)
	return a, b, c, a_ok && b_ok && c_ok && a >= 0 && b >= a && c > b
}
http_header :: proc "c" (data: rawptr, size, count: c.size_t, arg: rawptr) -> c.size_t {
	context = runtime.default_context()
	h := cast(^Http)arg
	n := int(size * count)
	line := string((cast([^]u8)data)[:n])
	if strings.has_prefix(line, "HTTP/") {
		clear(&h.bytes)
		h.first, h.last, h.length = -1, -1, -1
		space := strings.index_byte(line, ' ')
		if space >= 0 && space + 4 <= len(line) {
			status, ok := strconv.parse_int(line[space + 1:space + 4])
			if ok && status >= 300 && status < 400 {h.redirect_status = c.long(status)}
		}
	}
	if len(line) > 14 && strings.equal_fold(line[:14], "Content-Range:") {
		first, last, total, ok := parse_range(line[14:])
		if ok {h.first, h.last, h.length = first, last, total}
	}
	return c.size_t(n)
}
http_progress :: proc "c" (
	arg: rawptr,
	_: curl.off_t,
	_: curl.off_t,
	_: curl.off_t,
	_: curl.off_t,
) -> c.int {
	h := cast(^Http)arg
	return interrupt(&h.cancel)
}
valid_response :: proc(h: ^Http, at, end: i64, status: c.long) -> bool {
	return(
		status == 206 &&
		h.first == at &&
		h.length > at &&
		h.last == min(end, h.length - 1) &&
		i64(len(h.bytes)) == h.last - at + 1 &&
		(h.total < 0 || h.total == h.length) \
	)
}
http_prepare :: proc(h: ^Http, at, end: i64) -> curl.code {
	if h.handle == nil {return .E_FAILED_INIT}
	range := fmt.caprintf("%d-%d", at, end)
	defer delete(range)
	url := strings.clone_to_cstring(h.url)
	defer delete(url)
	clear(&h.bytes)
	h.first, h.last, h.length = -1, -1, -1
	h.redirect_status = 0
	curl.easy_reset(h.handle)
	curl.easy_setopt(h.handle, .URL, url) or_return
	curl.easy_setopt(h.handle, .RANGE, range) or_return
	version := h.mode == "curl-h3" ? curl.HTTP_VERSION_3ONLY : curl.HTTP_VERSION_1_1
	curl.easy_setopt(h.handle, .HTTP_VERSION, c.long(version)) or_return
	curl.easy_setopt(
		h.handle,
		.PROTOCOLS_STR,
		cstring(strings.has_prefix(h.url, "http://") ? "http,https" : "https"),
	) or_return
	curl.easy_setopt(h.handle, .FOLLOWLOCATION, c.long(1)) or_return
	curl.easy_setopt(h.handle, .MAXREDIRS, c.long(5)) or_return
	curl.easy_setopt(
		h.handle,
		.REDIR_PROTOCOLS_STR,
		cstring(strings.has_prefix(h.url, "http://") ? "http,https" : "https"),
	) or_return
	curl.easy_setopt(h.handle, .SSL_VERIFYPEER, c.long(1)) or_return
	curl.easy_setopt(h.handle, .SSL_VERIFYHOST, c.long(2)) or_return
	curl.easy_setopt(h.handle, .CAINFO, cstring("/etc/ssl/certs/ca-certificates.crt")) or_return
	curl.easy_setopt(h.handle, .USERAGENT, cstring("leantube")) or_return
	curl.easy_setopt(h.handle, .NOSIGNAL, c.long(1)) or_return
	curl.easy_setopt(h.handle, .SOCKOPTFUNCTION, http_socket_options) or_return
	curl.easy_setopt(h.handle, .SOCKOPTDATA, rawptr(h)) or_return
	curl.easy_setopt(h.handle, .CONNECTTIMEOUT_MS, c.long(5000)) or_return
	curl.easy_setopt(h.handle, .TIMEOUT_MS, c.long(15000)) or_return
	curl.easy_setopt(h.handle, .ACCEPT_ENCODING, cstring("identity")) or_return
	curl.easy_setopt(h.handle, .WRITEFUNCTION, http_write) or_return
	curl.easy_setopt(h.handle, .WRITEDATA, rawptr(h)) or_return
	curl.easy_setopt(h.handle, .HEADERFUNCTION, http_header) or_return
	curl.easy_setopt(h.handle, .HEADERDATA, rawptr(h)) or_return
	curl.easy_setopt(h.handle, .NOPROGRESS, c.long(0)) or_return
	curl.easy_setopt(h.handle, .XFERINFOFUNCTION, http_progress) or_return
	curl.easy_setopt(h.handle, .XFERINFODATA, rawptr(h)) or_return
	return .E_OK
}
http_finish :: proc(h: ^Http, at, end: i64, result: curl.code) -> bool {
	status, protocol, connections: c.long
	curl.easy_getinfo(h.handle, .RESPONSE_CODE, &status)
	curl.easy_getinfo(h.handle, .HTTP_VERSION, &protocol)
	curl.easy_getinfo(h.handle, .NUM_CONNECTS, &connections)
	h.transfers += 1
	h.connections += connections
	if protocol != 0 {h.protocol = protocol}
	valid :=
		result == .E_OK &&
		(h.mode != "curl-h3" || protocol == curl.HTTP_VERSION_3) &&
		valid_response(h, at, end, status)
	if h.trace {transport_sample(h, at, valid, result)}
	if !valid {
		if !cancelled(
			&h.cancel,
		) {fmt.eprintf("reader curl=%d status=%d offset=%d first=%d last=%d total=%d bytes=%d\n", result, status, at, h.first, h.last, h.length, len(h.bytes))}
		clear(&h.bytes)
		return false
	}
	// Redirects apply to this request. Keep the resolved source for later
	// ranges; libcurl can reuse connections to both origin and destination.
	h.total = h.length
	h.base = at
	return true
}
http_fetch :: proc(h: ^Http, at: i64) -> bool {
	end := at + i64(h.block) - 1
	if h.total >= 0 {end = min(end, h.total - 1)}
	if http_prepare(h, at, end) != .E_OK {return false}
	result := curl.easy_perform(h.handle)
	if (result == .E_RECV_ERROR || result == .E_PARTIAL_FILE) && !cancelled(&h.cancel) {
		// A range GET is safe to repeat. Discard partial bytes and retry once
		// on a new connection. Later requests return to normal reuse.
		http_finish(h, at, end, result)
		h.retries += 1
		if http_prepare(h, at, end) != .E_OK ||
		   curl.easy_setopt(h.handle, .FRESH_CONNECT, c.long(1)) != .E_OK {return false}
		result = curl.easy_perform(h.handle)
	}
	return http_finish(h, at, end, result)
}
http_close :: proc(h: ^Http) {
	curl.easy_cleanup(h.handle)
	delete(h.url); delete(h.bytes)
}

http_read :: proc "c" (arg: rawptr, output: [^]u8, size: c.int) -> c.int {
	context = runtime.default_context()
	h := cast(^Http)arg
	if cancelled(&h.cancel) {return ERROR_EXIT}
	if h.position >= h.total {return ERROR_EOF}
	if h.position < h.base || h.position >= h.base + i64(len(h.bytes)) {
		if !http_fetch(h, h.position) {return cancelled(&h.cancel) ? ERROR_EXIT : ERROR_IO}
	}
	offset := int(h.position - h.base)
	n := min(int(size), len(h.bytes) - offset)
	copy(output[:n], h.bytes[offset:][:n])
	h.position += i64(n)
	return c.int(n)
}
http_seek :: proc "c" (arg: rawptr, offset: i64, whence: c.int) -> i64 {
	h := cast(^Http)arg
	if whence & SEEK_SIZE != 0 {return h.total}
	at := i64(-1)
	switch whence & ~c.int(SEEK_FORCE) {
	case 0:
		at = offset
	case 1:
		at = h.position + offset
	case 2:
		at = h.total + offset
	}
	if at < 0 || at > h.total {return i64(ERROR_ARGUMENT)}
	h.position = at
	return at
}
