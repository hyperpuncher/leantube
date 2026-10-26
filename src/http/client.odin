package http

import "base:runtime"
import "core:c"
import "core:strings"
import curl "vendor:curl"

Failure :: enum {
	Invalid_Request = 1,
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
receive :: proc "c" (data: rawptr, size, count: c.size_t, user: rawptr) -> c.size_t {
	context = runtime.default_context()
	body := cast(^[dynamic]u8)user
	if size == 0 || count == 0 {return 0}
	n, error := append(body, ..(cast([^]u8)data)[:int(size * count)])
	return error == nil ? c.size_t(n) : 0
}

// The caller owns response.body, including non-2xx responses. Errors return no
// body. Redirects are returned, not followed, to prevent silent HTTPS downgrades.
request :: proc(
	client: ^Client,
	url: string,
	post_body: Maybe(string) = nil,
	headers: []string = nil,
	timeout_ms: c.long = 15000,
) -> (
	response: Response,
	error: Error,
) {
	if client.handle == nil ||
	   !strings.has_prefix(url, "https://") ||
	   timeout_ms <= 0 {return {}, Failure.Invalid_Request}
	handle := client.handle
	// Reset request state while retaining libcurl's connection and TLS caches.
	curl.easy_reset(handle)
	target := strings.clone_to_cstring(url)
	defer delete(target)
	response_body := make([dynamic]u8, 0, 4096)
	defer if error != nil {delete(response_body)}
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
	curl.easy_setopt(handle, .WRITEDATA, rawptr(&response_body)) or_return
	curl.easy_setopt(handle, .HTTPHEADER, list) or_return
	if client.ca_file != nil {curl.easy_setopt(handle, .CAINFO, client.ca_file) or_return}
	if post_body != nil {
		posted := post_body.(string)
		curl.easy_setopt(handle, .POST, c.long(1)) or_return
		curl.easy_setopt(handle, .POSTFIELDSIZE, c.long(len(posted))) or_return
		curl.easy_setopt(handle, .POSTFIELDS, raw_data(posted)) or_return
	}
	code := curl.easy_perform(handle)
	if code != .E_OK {return {}, code}
	curl.easy_getinfo(handle, .RESPONSE_CODE, &response.status) or_return
	response.body = response_body
	return response, nil
}
