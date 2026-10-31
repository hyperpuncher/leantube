package playback

import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:net"
import "core:strings"
import curl "vendor:curl"

transport_host :: proc(url: cstring) -> string {
	if url == nil {return ""}
	scheme, host, _, query, _ := net.split_url(string(url))
	defer delete(query)
	// Do not emit user information, paths, fragments, or signed queries.
	if (scheme != "http" && scheme != "https") || strings.contains(host, "@") {return ""}
	return strings.clone(host)
}
transport_sample :: proc(h: ^Http, at: i64, valid: bool, result: curl.code) {
	primary, effective: cstring
	dns, connect, first, total, received: curl.off_t
	proxy: c.long
	curl.easy_getinfo(h.handle, .PRIMARY_IP, &primary)
	curl.easy_getinfo(h.handle, .EFFECTIVE_URL, &effective)
	curl.easy_getinfo(h.handle, .NAMELOOKUP_TIME_T, &dns)
	curl.easy_getinfo(h.handle, .CONNECT_TIME_T, &connect)
	curl.easy_getinfo(h.handle, .STARTTRANSFER_TIME_T, &first)
	curl.easy_getinfo(h.handle, .TOTAL_TIME_T, &total)
	curl.easy_getinfo(h.handle, .SIZE_DOWNLOAD_T, &received)
	curl.easy_getinfo(h.handle, .USED_PROXY, &proxy)
	host := transport_host(effective)
	defer delete(host)
	row := struct {
		event, track:                                                        string,
		elapsed_s:                                                           f64,
		transfer:                                                            c.long,
		offset, received_bytes:                                              i64,
		complete:                                                            bool,
		curl_code:                                                           curl.code,
		server_host, server_address:                                         string,
		protocol, proxy_used, connections, receive_retries, redirect_status: c.long,
		socket_rcvbuf_requested, socket_rcvbuf_actual:                       c.int,
		dns_us, connect_us, first_byte_us, total_us:                         i64,
	} {
		"http_transfer",
		h.label,
		seconds_since(h.begun),
		h.transfers,
		at,
		i64(received),
		valid,
		result,
		host,
		primary == nil ? "" : string(primary),
		h.protocol,
		proxy,
		h.connections,
		h.retries,
		h.redirect_status,
		h.receive_buffer_request,
		h.receive_buffer_actual,
		i64(dns),
		i64(connect),
		i64(first),
		i64(total),
	}
	encoded, error := json.marshal(row)
	if error == nil {fmt.println(string(encoded)); delete(encoded)}
}
