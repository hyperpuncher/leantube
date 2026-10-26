#+test
package youtube

import "../http"
import "core:testing"

thumbnail_calls, thumbnail_success_at: int
thumbnail_failure_status: int

fake_thumbnail_fetch :: proc(_: ^http.Client, url: string) -> (http.Response, http.Error) {
	thumbnail_calls += 1
	if thumbnail_calls ==
	   1 {assert(url == "https://i.ytimg.com/vi_webp/aqz-KE-bpKQ/maxresdefault.webp")}
	status := thumbnail_calls == thumbnail_success_at ? 200 : thumbnail_failure_status
	body := make([dynamic]u8)
	append(&body, "RIFF-original-WEBP-bytes")
	return {status = auto_cast status, body = body}, nil
}

@(test)
thumbnail_fallback_preserves_bytes_and_never_accepts_a_404_image :: proc(t: ^testing.T) {
	for at in ([]int{1, 2, 5, 8, 0}) {
		thumbnail_calls, thumbnail_success_at, thumbnail_failure_status = 0, at, 404
		bytes := thumbnail(nil, "aqz-KE-bpKQ", fetch = fake_thumbnail_fetch)
		if at > 0 {
			testing.expect_value(t, string(bytes[:]), "RIFF-original-WEBP-bytes")
			testing.expect_value(t, thumbnail_calls, at)
		} else {
			testing.expect_value(t, len(bytes), 0)
			testing.expect_value(t, thumbnail_calls, 8)
		}
		delete(bytes)
	}
	thumbnail_calls, thumbnail_success_at, thumbnail_failure_status = 0, 0, 503
	bytes := thumbnail(nil, "aqz-KE-bpKQ", fetch = fake_thumbnail_fetch)
	defer delete(bytes)
	testing.expect_value(t, len(bytes), 0)
	testing.expect_value(t, thumbnail_calls, 1)
	thumbnail_calls = 0
	canceled := thumbnail(
		nil,
		"aqz-KE-bpKQ",
		stop_when = proc() -> bool {return true},
		fetch = fake_thumbnail_fetch,
	)
	defer delete(canceled)
	testing.expect_value(t, thumbnail_calls, 0)
}
