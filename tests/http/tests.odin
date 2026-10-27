#+test
package main

import http "../../src/http"
import yt "../../src/youtube"
import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import curl "vendor:curl"

// Redirect only the external boundary. Header construction and TLS are real.
local_youtube_request :: proc(
	client: ^http.Client,
	url: string,
	post_body: Maybe(string),
	headers: []string,
	timeout_ms: c.long,
	follow_redirects: bool,
) -> (
	http.Response,
	http.Error,
) {
	base := os.get_env("LEANTUBE_TEST_HTTPS", context.allocator)
	defer delete(base)
	local_url, _ := strings.replace_all(url, "https://www.youtube.com", base)
	defer delete(local_url)
	return http.request(client, local_url, post_body, headers, timeout_ms, follow_redirects)
}

@(test)
youtube_authorization_survives_until_transfer_and_is_not_reused :: proc(t: ^testing.T) {
	base := os.get_env("LEANTUBE_TEST_HTTPS", context.allocator)
	ca_file := os.get_env("LEANTUBE_TEST_CA", context.allocator)
	defer {delete(base); delete(ca_file)}
	client, error := http.open(ca_file)
	if !testing.expect_value(t, error, nil) {return}
	defer http.close(&client)
	yt.set_access_token("local-test-token")
	defer yt.set_access_token("")
	body := `{"context":{}}`
	response, request_error := yt.api_post(
		&client,
		"account/accounts_list",
		transmute([]u8)body,
		.TV,
		request = local_youtube_request,
	)
	defer delete(response.body)
	testing.expect_value(t, request_error, .None)
	testing.expect_value(t, string(response.body[:]), "authorized")
	anonymous, anonymous_error := http.request(&client, base)
	defer delete(anonymous.body)
	testing.expect_value(t, anonymous_error, nil)
	testing.expect_value(t, int(anonymous.status), 200)
}

@(test)
https_rejects_untrusted_certificates_wrong_hosts_and_downgrades :: proc(t: ^testing.T) {
	base := os.get_env("LEANTUBE_TEST_HTTPS", context.allocator)
	ca_file := os.get_env("LEANTUBE_TEST_CA", context.allocator)
	defer {delete(base); delete(ca_file)}
	client, error := http.open()
	if !testing.expect_value(t, error, nil) {return}
	defer http.close(&client)
	response, request_error := http.request(&client, base)
	defer delete(response.body)
	testing.expect_value(t, request_error, http.Error(curl.code.E_PEER_FAILED_VERIFICATION))
	trusted, trusted_error := http.open(ca_file)
	if !testing.expect_value(t, trusted_error, nil) {return}
	defer http.close(&trusted)
	insecure, insecure_error := http.request(&trusted, "http://localhost")
	defer delete(insecure.body)
	// A zero-valued failure in a shared-nil union would look like success.
	testing.expect(t, insecure_error != nil)
	testing.expect_value(t, insecure_error, http.Error(http.Failure.Invalid_Request))
	wrong_host, _ := strings.replace_all(base, "localhost", "127.0.0.1")
	defer delete(wrong_host)
	wrong, wrong_error := http.request(&trusted, wrong_host)
	defer delete(wrong.body)
	testing.expect_value(t, wrong_error, http.Error(curl.code.E_PEER_FAILED_VERIFICATION))
	redirect, redirect_error := http.request(&trusted, fmt.tprintf("%s/redirect", base))
	defer delete(redirect.body)
	testing.expect_value(t, redirect_error, nil)
	testing.expect_value(t, int(redirect.status), 302)
}

@(test)
media_ranges_follow_https_redirects_without_allowing_downgrades_or_credentials :: proc(
	t: ^testing.T,
) {
	base := os.get_env("LEANTUBE_TEST_HTTPS", context.allocator)
	ca_file := os.get_env("LEANTUBE_TEST_CA", context.allocator)
	defer {delete(base); delete(ca_file)}
	client, error := http.open(ca_file)
	if !testing.expect_value(t, error, nil) {return}
	defer http.close(&client)
	bytes, ok := yt.fetch_range(&client, fmt.tprintf("%s/range-redirect", base), 3, 5)
	defer delete(bytes)
	testing.expect(t, ok)
	testing.expect_value(t, string(bytes), "def")
	for endpoint, i in ([]string{"redirect", "redirect-loop", "redirect-wrong-host"}) {
		response, request_error := http.request(
			&client,
			fmt.tprintf("%s/%s", base, endpoint),
			follow_redirects = true,
		)
		defer delete(response.body)
		expected := [?]curl.code {
			.E_UNSUPPORTED_PROTOCOL,
			.E_TOO_MANY_REDIRECTS,
			.E_PEER_FAILED_VERIFICATION,
		}
		testing.expect_value(t, request_error, http.Error(expected[i]))
	}
	for header in ([]string{"Authorization: Bearer test-only", "cOoKiE: test-only=value"}) {
		response, request_error := http.request(
			&client,
			base,
			headers = {header},
			follow_redirects = true,
		)
		defer delete(response.body)
		testing.expect_value(t, request_error, http.Error(http.Failure.Invalid_Request))
	}
	// Redirect state is reset before the next API request.
	response, request_error := http.request(&client, fmt.tprintf("%s/range-redirect", base))
	defer delete(response.body)
	testing.expect_value(t, request_error, nil)
	testing.expect_value(t, int(response.status), 302)
}

@(test)
request_reuse_discards_post_state_and_recovers_after_failures :: proc(t: ^testing.T) {
	base := os.get_env("LEANTUBE_TEST_HTTPS", context.allocator)
	ca_file := os.get_env("LEANTUBE_TEST_CA", context.allocator)
	defer {delete(base); delete(ca_file)}
	client, error := http.open(ca_file)
	if !testing.expect_value(t, error, nil) {return}
	defer http.close(&client)
	body := `{"title":"café"}`
	posted, post_error := http.request(
		&client,
		fmt.tprintf("%s/post", base),
		body,
		{"X-LeanTube-Test: set"},
	)
	defer delete(posted.body)
	testing.expect_value(t, post_error, nil)
	testing.expect_value(t, string(posted.body[:]), body)
	// The fixture rejects leaked POST methods, headers, or bodies on GET.
	timed_out, timeout_error := http.request(
		&client,
		fmt.tprintf("%s/slow", base),
		timeout_ms = 100,
	)
	testing.expect_value(t, timeout_error, http.Error(curl.code.E_OPERATION_TIMEDOUT))
	testing.expect_value(t, len(timed_out.body), 0)
	delete(timed_out.body)
	response, response_error := http.request(&client, base)
	testing.expect_value(t, response_error, nil)
	testing.expect_value(t, int(response.status), 200)
	testing.expect_value(t, string(response.body[:]), "ready")
	delete(response.body)
}
