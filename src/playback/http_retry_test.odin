package playback

import "core:c"
import "core:fmt"
import "core:sync"
import "core:testing"
import curl "vendor:curl"

HTTP_TEST_SERVER :: #config(READER_HTTP_TEST_SERVER, "")
@(test)
temporary_redirects_apply_to_one_range_not_the_whole_source :: proc(t: ^testing.T) {
	testing.expect(t, HTTP_TEST_SERVER != "")
	if HTTP_TEST_SERVER == "" {return}
	testing.expect_value(t, curl.global_init(c.long(curl.GLOBAL_DEFAULT)), curl.code.E_OK)
	defer curl.global_cleanup()
	s := State{}
	h := Http {
		cancel = {state = &s},
		handle = curl.easy_init(),
		url = fmt.aprintf("%s/redirect", HTTP_TEST_SERVER),
		mode = "curl-reuse",
		block = 16,
		total = -1,
	}
	defer http_close(&h)
	testing.expect(t, http_fetch(&h, 0))
	testing.expect_value(t, string(h.bytes[:]), "0123456789abcdef")
	testing.expect(t, http_fetch(&h, 16))
	testing.expect_value(t, string(h.bytes[:]), "ghijklmnopqrstuv")
}
// Run with just test-reader-http so the local failure fixture is present.
@(test)
interrupted_ranges_retry_once_without_returning_partial_bytes :: proc(t: ^testing.T) {
	testing.expect(t, HTTP_TEST_SERVER != "")
	if HTTP_TEST_SERVER == "" {return}
	testing.expect_value(t, curl.global_init(c.long(curl.GLOBAL_DEFAULT)), curl.code.E_OK)
	defer curl.global_cleanup()
	for path in ([]string{"/once", "/always", "/timeout"}) {
		s := State{}
		h := Http {
			cancel = {state = &s},
			handle = curl.easy_init(),
			url = fmt.aprintf("%s%s", HTTP_TEST_SERVER, path),
			mode = path == "/timeout" ? "curl-auto" : "curl-reuse",
			block = 16,
			total = 64,
		}
		defer http_close(&h)
		bytes: [16]u8
		result := http_read(&h, raw_data(bytes[:]), len(bytes))
		if path == "/always" {
			testing.expect_value(t, result, ERROR_IO)
			testing.expect_value(t, sync.atomic_load(&s.failure), ERROR_IO)
			testing.expect_value(t, len(h.bytes), 0)
		} else {
			testing.expect_value(t, result, c.int(len(bytes)))
			testing.expect_value(t, string(bytes[:]), "0123456789abcdef")
		}
	}
}
