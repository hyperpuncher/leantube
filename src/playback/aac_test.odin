package playback

import "core:c"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:testing"

@(test)
aac_configuration_rejects_unsupported_framing :: proc(t: ^testing.T) {
	config, ok := aac_config({0x12, 0x10})
	testing.expect(t, ok)
	testing.expect_value(t, config.rate, 44100)
	testing.expect_value(t, config.channels, 2)
	eight, eight_ok := aac_config({0x12, 0x38})
	testing.expect(t, eight_ok && eight.channels == 8)
	for asc in ([][2]u8{{0x2a, 0x10}, {0x17, 0x90}, {0x12, 0x00}, {0x12, 0x11}}) {
		_, valid := aac_config(asc)
		testing.expect(t, !valid)
	}
}
@(test)
adts_mux_preserves_aac_payload_and_timestamps :: proc(t: ^testing.T) {
	url := strings.clone_to_cstring(fmt.tprintf("%s/audio", HTTP_TEST_SERVER))
	defer delete(url)
	input: ^AVFormatContext
	testing.expect(t, avformat_open_input(&input, url, nil, nil) >= 0)
	if input == nil {return}
	defer avformat_close_input(&input)
	testing.expect(t, avformat_find_stream_info(input, nil) >= 0)
	index := av_find_best_stream(input, 1, -1, -1, nil, 0)
	testing.expect(t, index >= 0)
	if index < 0 {return}
	mux := framing_muxer(input.streams[index].codecpar, "adts")
	testing.expect(t, mux != nil)
	if mux == nil {return}
	defer avformat_free_context(mux)
	packet := av_packet_alloc()
	defer av_packet_free(&packet)
	testing.expect(t, av_read_frame(input, packet) >= 0)
	original := make([]u8, int(packet.size))
	copy(original, packet.data[:packet.size])
	defer delete(original)
	pts, dts, duration := packet.pts, packet.dts, packet.duration
	testing.expect(t, framing_frame(mux, &packet))
	testing.expect_value(t, packet.size, c.int(len(original) + 7))
	testing.expect_value(t, packet.pts, pts)
	testing.expect_value(t, packet.dts, dts)
	testing.expect_value(t, packet.duration, duration)
	testing.expect(t, mem.compare(packet.data[7:packet.size], original) == 0)
	testing.expect_value(t, packet.data[0], u8(0xff))
	testing.expect_value(t, packet.data[1], u8(0xf1))
}
