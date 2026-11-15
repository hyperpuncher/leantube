#+build wasi
package http

import "core:c"

// The web demo has no HTTP transport. Its catalog replaces the network
// worker, so these keep the shared YouTube and SponsorBlock code compiling.
Failure :: enum {
	Invalid_Request = 1,
}
Error :: union #shared_nil {
	Failure,
}
Client :: struct {}
Response :: struct {
	status: c.long,
	body:   [dynamic]u8,
}

request :: proc(
	client: ^Client,
	url: string,
	post_body: Maybe(string) = nil,
	headers: []string = nil,
	timeout_ms: c.long = 15000,
	follow_redirects: bool = false,
) -> (
	response: Response,
	error: Error,
) {
	return {}, Failure.Invalid_Request
}
