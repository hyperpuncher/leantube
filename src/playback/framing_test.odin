package playback

import "core:fmt"
import "core:mem"
import "core:testing"

@(test)
video_muxers_add_native_framing_without_changing_timestamps :: proc(t: ^testing.T) {
	for codec in ([]cstring{"h264", "hevc", "av1"}) {
		url := fmt.caprintf("%s/%s", HTTP_TEST_SERVER, codec)
		defer delete(url)
		input: ^AVFormatContext
		testing.expect(t, avformat_open_input(&input, url, nil, nil) >= 0)
		if input == nil {continue}
		defer avformat_close_input(&input)
		testing.expect(t, avformat_find_stream_info(input, nil) >= 0)
		index := av_find_best_stream(input, 0, -1, -1, nil, 0)
		testing.expect(t, index >= 0)
		if index < 0 {continue}
		mux := framing_muxer(
			input.streams[index].codecpar,
			string(codec) == "av1" ? cstring("obu") : codec,
		)
		testing.expect(t, mux != nil)
		if mux == nil {continue}
		defer avformat_free_context(mux)
		p := av_packet_alloc()
		defer av_packet_free(&p)
		testing.expect(t, av_read_frame(input, p) >= 0)
		original := make([]u8, int(p.size))
		copy(original, p.data[:p.size])
		defer delete(original)
		pts, dts, duration := p.pts, p.dts, p.duration
		testing.expect(t, framing_frame(mux, &p))
		testing.expect_value(t, p.pts, pts)
		testing.expect_value(t, p.dts, dts)
		testing.expect_value(t, p.duration, duration)
		if string(codec) == "av1" {
			// The temporal delimiter is framing, not re-encoded picture data.
			testing.expect(t, p.size >= 2 && p.data[0] == 0x12 && p.data[1] == 0)
		} else {
			testing.expect(t, p.size > 4 && mem.compare(p.data[:4], []u8{0, 0, 0, 1}) == 0)
			// MP4 uses a four-byte NAL length. Annex B uses a start code.
			// The original first NAL payload must remain present byte for byte.
			nal_size :=
				int(original[0]) << 24 |
				int(original[1]) << 16 |
				int(original[2]) << 8 |
				int(original[3])
			found := false
			for at := 0; at + nal_size <= int(p.size); at += 1 {
				if mem.compare(p.data[at:at + nal_size], original[4:4 + nal_size]) ==
				   0 {found = true; break}
			}
			testing.expect(t, found)
		}
	}
}
