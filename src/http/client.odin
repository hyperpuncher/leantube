package http

import "base:runtime"
import "core:c"
import "core:strings"
import curl "vendor:curl"

Failure :: enum {
	None,
	Invalid_Request,
	Body_Limit,
}
Error :: union #shared_nil {
	curl.code,
	Failure,
}
Client :: struct {
	handle:  ^curl.CURL,
	ca_file: cstring,
}
Response :: struct {
	status: c.long,
	body:   [dynamic]u8,
}

// Open before starting the network worker; close after joining it. Keep HTTPS
// on one worker for the B9's OpenSSL 1.0.2. Requests must stay off the UI thread.
open :: proc(ca_file: string = "") -> (client: Client, error: Error) {
	curl.global_init(c.long(curl.GLOBAL_DEFAULT)) or_return
	client.handle = curl.easy_init()
	if client.handle == nil {curl.global_cleanup(); return {}, curl.code.E_OUT_OF_MEMORY}
	if ca_file != "" {client.ca_file = strings.clone_to_cstring(ca_file)}
	return client, nil
}

close :: proc(client: ^Client) {
	if client.handle == nil {return}
	curl.easy_cleanup(client.handle)
	delete(client.ca_file)
	curl.global_cleanup()
	client^ = {}
}

@(private)
Capture :: struct {
	body:    [dynamic]u8,
	limit:   int,
	limited: bool,
}

@(private)
receive :: proc "c" (data: rawptr, size, count: c.size_t, user: rawptr) -> c.size_t {
	context = runtime.default_context()
	capture := cast(^Capture)user
	if size == 0 || count == 0 {return 0}
	if count > c.size_t(capture.limit - len(capture.body)) / size {
		capture.limited = true
		return 0
	}
	n, error := append(&capture.body, ..(cast([^]u8)data)[:int(size * count)])
	return error == nil ? c.size_t(n) : 0
}

// The caller owns response.body, including non-2xx responses. Errors return no
// body. Redirects are returned, not followed, to prevent silent HTTPS downgrades.
request :: proc(
	client: ^Client,
	url: string,
	post_body: Maybe(string) = nil,
	headers: []string = nil,
	max_bytes: int = 2 * 1024 * 1024,
	timeout_ms: c.long = 15000,
) -> (
	response: Response,
	error: Error,
) {
	if client.handle == nil ||
	   !strings.has_prefix(url, "https://") ||
	   max_bytes <= 0 ||
	   timeout_ms <= 0 {return {}, Failure.Invalid_Request}
	handle := client.handle
	// Reset request state while retaining libcurl's connection and TLS caches.
	curl.easy_reset(handle)
	target := strings.clone_to_cstring(url)
	defer delete(target)
	capture := Capture {
		body  = make([dynamic]u8, 0, min(max_bytes, 4096)),
		limit = max_bytes,
	}
	defer if error != nil {delete(capture.body)}
	list: ^curl.slist
	defer curl.slist_free_all(list)
	for header in headers {
		text := strings.clone_to_cstring(header)
		next := curl.slist_append(list, text)
		delete(text)
		if next == nil {return {}, curl.code.E_OUT_OF_MEMORY}
		list = next
	}
	curl.easy_setopt(handle, .SSL_VERIFYPEER, c.long(1)) or_return
	curl.easy_setopt(handle, .SSL_VERIFYHOST, c.long(2)) or_return
	curl.easy_setopt(handle, .NOSIGNAL, c.long(1)) or_return
	curl.easy_setopt(handle, .CONNECTTIMEOUT_MS, c.long(5000)) or_return
	curl.easy_setopt(handle, .TIMEOUT_MS, timeout_ms) or_return
	curl.easy_setopt(handle, .URL, target) or_return
	curl.easy_setopt(handle, .USERAGENT, cstring("leantube")) or_return
	curl.easy_setopt(handle, .WRITEFUNCTION, receive) or_return
	curl.easy_setopt(handle, .WRITEDATA, rawptr(&capture)) or_return
	curl.easy_setopt(handle, .HTTPHEADER, list) or_return
	if client.ca_file != nil {curl.easy_setopt(handle, .CAINFO, client.ca_file) or_return}
	if post_body != nil {
		body := post_body.(string)
		curl.easy_setopt(handle, .POST, c.long(1)) or_return
		curl.easy_setopt(handle, .POSTFIELDSIZE, c.long(len(body))) or_return
		curl.easy_setopt(handle, .POSTFIELDS, raw_data(body)) or_return
	}
	code := curl.easy_perform(handle)
	if capture.limited {return {}, Failure.Body_Limit}
	if code != .E_OK {return {}, code}
	curl.easy_getinfo(handle, .RESPONSE_CODE, &response.status) or_return
	response.body = capture.body
	return response, nil
}
