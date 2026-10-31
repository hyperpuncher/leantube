package diagnostics

import reader "../../../src/playback"
import "core:c"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
import curl "vendor:curl"

Transport_Options :: struct {
	mode:   string,
	count:  int,
	offset: i64,
}
transport_options :: proc(args: []string) -> (o: Transport_Options, ok: bool) {
	if len(args) != 3 {return}
	o.mode = args[0]
	if o.mode != "curl-reuse" && o.mode != "curl-h3" {return}
	count, count_ok := strconv.parse_int(args[1])
	offset, offset_ok := strconv.parse_i64(args[2])
	if !count_ok ||
	   !offset_ok ||
	   count < 1 ||
	   count > 256 ||
	   offset < 0 ||
	   offset > max(i64) - i64(count) * reader.BLOCK_BYTES {return}
	o.count, o.offset = count, offset
	return o, true
}
transport_entry :: proc(args: []string) -> int {
	o, ok := transport_options(args)
	if !ok {fmt.eprintln("expected MODE MIB BYTE_OFFSET; mode curl-reuse or curl-h3, 1..256 MiB"); return 2}
	receive_buffer, setting_ok := receive_buffer_setting()
	if !setting_ok {return 2}
	data, error := os.read_entire_file(os.stdin, context.allocator)
	if error != nil {return 2}
	defer delete(data)
	lines := strings.split(string(data), "\n")
	defer delete(lines)
	if len(lines) < 1 ||
	   (!strings.has_prefix(lines[0], "https://") &&
			   !strings.has_prefix(lines[0], "http://")) {return 2}
	if curl.global_init(c.long(curl.GLOBAL_DEFAULT)) != .E_OK {return 3}
	defer curl.global_cleanup()
	s := reader.State{}
	begun := time.tick_now()
	h := reader.Http {
		cancel = {state = &s},
		handle = curl.easy_init(),
		url = strings.clone(lines[0]),
		mode = o.mode,
		receive_buffer_request = receive_buffer,
		block = reader.BLOCK_BYTES,
		total = -1,
		trace = true,
		label = "video",
		begun = begun,
	}
	defer reader.http_close(&h)
	fmt.printf("{{\"curl_version\":\"%s\"}}\n", curl.version())
	completed := 0
	for i in 0 ..< o.count {
		if reader.seconds_since(begun) >= 60 {break}
		at := o.offset + i64(i) * reader.BLOCK_BYTES
		if !reader.http_fetch(&h, at) || len(h.bytes) != reader.BLOCK_BYTES {break}
		completed += 1
	}
	elapsed := reader.seconds_since(begun)
	fmt.printf(
		"{{\"summary\":true,\"transport_only\":true,\"completed_mib\":%d,\"requested_mib\":%d,\"elapsed_s\":%.3f,\"megabits_per_second\":%.3f,\"connections\":%d,\"receive_retries\":%d,\"max_rss_kib\":%d}}\n",
		completed,
		o.count,
		elapsed,
		f64(completed * reader.BLOCK_BYTES) * 8 / elapsed / 1e6,
		h.connections,
		h.retries,
		peak_rss_kib(),
	)
	return completed == o.count ? 0 : 1
}
