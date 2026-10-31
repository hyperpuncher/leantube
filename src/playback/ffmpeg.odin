package playback

import "core:c"

// FFmpeg 9 (libavformat 63, libavcodec 63, libavutil 61).
// These are public structure prefixes, not allocation sizes. FFmpeg owns and
// allocates every instance. Keep the field order from the upstream headers.
Rational :: struct {
	num, den: c.int,
}
AVPacket :: struct {
	buf:                       rawptr,
	pts, dts:                  i64,
	data:                      [^]u8,
	size, stream_index, flags: c.int,
	side_data:                 rawptr,
	side_data_elems:           c.int,
	duration:                  i64,
}
Codec_Parameters :: struct {
	codec_type, codec_id:                                                               c.int,
	codec_tag:                                                                          u32,
	extradata:                                                                          rawptr,
	extradata_size:                                                                     c.int,
	coded_side_data:                                                                    rawptr,
	nb_coded_side_data, format:                                                         c.int,
	bit_rate:                                                                           i64,
	bits_per_coded_sample, bits_per_raw_sample, profile, level, width, height:          c.int,
	sample_aspect_ratio, framerate:                                                     Rational,
	field_order, color_range, color_primaries, color_trc, color_space, chroma_location: c.int,
}
when ODIN_ARCH == .arm32 {
	#assert(offset_of(Codec_Parameters, color_trc) == 92)
} else when ODIN_ARCH == .amd64 {
	#assert(offset_of(Codec_Parameters, color_trc) == 108)
}
AVStream :: struct {
	av_class:  rawptr,
	index, id: c.int,
	codecpar:  ^Codec_Parameters,
	priv_data: rawptr,
	time_base: Rational,
}
Interrupt :: struct {
	callback: proc "c" (_: rawptr) -> c.int,
	opaque:   rawptr,
}
AVFormatContext :: struct {
	av_class, iformat, oformat, priv_data:                            rawptr,
	pb:                                                               ^AVIOContext,
	ctx_flags:                                                        c.int,
	nb_streams:                                                       c.uint,
	streams:                                                          [^]^AVStream,
	nb_stream_groups:                                                 c.uint,
	stream_groups:                                                    rawptr,
	nb_chapters:                                                      c.uint,
	chapters:                                                         rawptr,
	url:                                                              cstring,
	start_time, duration, bit_rate:                                   i64,
	packet_size:                                                      c.uint,
	max_delay, flags:                                                 c.int,
	probesize, max_analyze_duration:                                  i64,
	key:                                                              rawptr,
	keylen:                                                           c.int,
	nb_programs:                                                      c.uint,
	programs:                                                         rawptr,
	video_codec_id, audio_codec_id, subtitle_codec_id, data_codec_id: c.int,
	metadata:                                                         rawptr,
	start_time_realtime:                                              i64,
	fps_probe_size, error_recognition:                                c.int,
	interrupt_callback:                                               Interrupt,
}
Read_Callback :: #type proc "c" (_: rawptr, _: [^]u8, _: c.int) -> c.int
Seek_Callback :: #type proc "c" (_: rawptr, _: i64, _: c.int) -> i64
AVIOContext :: struct {
	av_class:                                                         rawptr,
	buffer:                                                           rawptr,
	buffer_size:                                                      c.int,
	buf_ptr, buf_end, opaque:                                         rawptr,
	read_packet:                                                      Read_Callback,
	write_packet:                                                     rawptr,
	seek:                                                             Seek_Callback,
	pos:                                                              i64,
	eof_reached, error, write_flag, max_packet_size, min_packet_size: c.int,
	checksum:                                                         c.ulong,
	checksum_ptr, update_checksum, read_pause, read_seek:             rawptr,
	seekable, direct:                                                 c.int,
	protocol_whitelist, protocol_blacklist, write_data_type:          rawptr,
	ignore_boundary_point:                                            c.int,
	buf_ptr_max:                                                      rawptr,
	bytes_read:                                                       i64,
}
AVDictionary :: struct {}
NO_PTS :: i64(-1 << 63)
ERROR_EOF :: c.int(-541478725)
ERROR_EXIT :: c.int(-1414092869)
ERROR_INVALID_DATA :: c.int(-1094995529)
ERROR_IO :: c.int(-5)
ERROR_MEMORY :: c.int(-12)
ERROR_ARGUMENT :: c.int(-22)
SEEK_SIZE :: 0x10000
SEEK_FORCE :: 0x20000

foreign import avformat "system:avformat"
foreign avformat {
	avformat_alloc_output_context2 :: proc(_: ^^AVFormatContext, _: rawptr, _: cstring, _: cstring) -> c.int ---
	avformat_new_stream :: proc(_: ^AVFormatContext, _: rawptr) -> ^AVStream ---
	avformat_write_header :: proc(_: ^AVFormatContext, _: ^^AVDictionary) -> c.int ---
	av_write_frame :: proc(_: ^AVFormatContext, _: ^AVPacket) -> c.int ---
	avformat_free_context :: proc(_: ^AVFormatContext) ---
	avio_open_dyn_buf :: proc(_: ^^AVIOContext) -> c.int ---
	avio_close_dyn_buf :: proc(_: ^AVIOContext, _: ^[^]u8) -> c.int ---
	avformat_version :: proc() -> c.uint ---
	avformat_alloc_context :: proc() -> ^AVFormatContext ---
	avformat_open_input :: proc(_: ^^AVFormatContext, _: cstring, _: rawptr, _: ^^AVDictionary) -> c.int ---
	avformat_find_stream_info :: proc(_: ^AVFormatContext, _: rawptr) -> c.int ---
	av_find_best_stream :: proc(_: ^AVFormatContext, _: c.int, _: c.int, _: c.int, _: rawptr, _: c.int) -> c.int ---
	av_guess_frame_rate :: proc(_: ^AVFormatContext, _: ^AVStream, _: rawptr) -> Rational ---
	av_seek_frame :: proc(_: ^AVFormatContext, _: c.int, _: i64, _: c.int) -> c.int ---
	av_read_frame :: proc(_: ^AVFormatContext, _: ^AVPacket) -> c.int ---
	avformat_close_input :: proc(_: ^^AVFormatContext) ---
	avio_alloc_context :: proc(_: rawptr, _: c.int, _: c.int, _: rawptr, _: Read_Callback, _: rawptr, _: Seek_Callback) -> ^AVIOContext ---
	avio_context_free :: proc(_: ^^AVIOContext) ---
}
foreign import avcodec "system:avcodec"
foreign avcodec {
	avcodec_parameters_copy :: proc(_: ^Codec_Parameters, _: ^Codec_Parameters) -> c.int ---
	avcodec_get_name :: proc(_: c.int) -> cstring ---
	av_packet_from_data :: proc(_: ^AVPacket, _: [^]u8, _: c.int) -> c.int ---
	av_packet_copy_props :: proc(_: ^AVPacket, _: ^AVPacket) -> c.int ---
	avcodec_version :: proc() -> c.uint ---
	av_packet_alloc :: proc() -> ^AVPacket ---
	av_packet_free :: proc(_: ^^AVPacket) ---
}
foreign import avutil "system:avutil"
foreign avutil {
	avutil_version :: proc() -> c.uint ---
	av_version_info :: proc() -> cstring ---
	av_log_set_level :: proc(_: c.int) ---
	av_log_set_callback :: proc(_: proc "c" (_: rawptr, _: c.int, _: cstring, _: rawptr)) ---
	av_log_format_line2 :: proc(_: rawptr, _: c.int, _: cstring, _: rawptr, _: [^]u8, _: c.int, _: ^c.int) -> c.int ---
	av_malloc :: proc(_: c.size_t) -> rawptr ---
	av_freep :: proc(_: rawptr) ---
	av_dict_set :: proc(_: ^^AVDictionary, _: cstring, _: cstring, _: c.int) -> c.int ---
	av_dict_free :: proc(_: ^^AVDictionary) ---
}
