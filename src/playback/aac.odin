package playback

// ADTS is container framing only. The AAC access unit is not re-encoded.
Aac_Config :: struct {
	rate, channels: int,
}
aac_config :: proc(asc: [2]u8) -> (config: Aac_Config, ok: bool) {
	object := asc[0] >> 3
	frequency := ((asc[0] & 7) << 1) | (asc[1] >> 7)
	channels := (asc[1] >> 3) & 15
	rates := [13]int {
		96000,
		88200,
		64000,
		48000,
		44100,
		32000,
		24000,
		22050,
		16000,
		12000,
		11025,
		8000,
		7350,
	}
	if object != 2 || frequency >= 13 || channels == 0 || channels > 7 || asc[1] & 7 != 0 {return}
	return {rates[frequency], int(channels)}, true
}
aac_muxer :: proc(parameters: ^Codec_Parameters) -> ^AVFormatContext {
	mux: ^AVFormatContext
	if avformat_alloc_output_context2(&mux, nil, "adts", nil) < 0 {return nil}
	stream := avformat_new_stream(mux, nil)
	if stream == nil ||
	   avcodec_parameters_copy(stream.codecpar, parameters) < 0 ||
	   avio_open_dyn_buf(&mux.pb) < 0 {
		avformat_free_context(mux)
		return nil
	}
	result := avformat_write_header(mux, nil)
	data: [^]u8
	avio_close_dyn_buf(mux.pb, &data)
	av_freep(&data)
	mux.pb = nil
	if result < 0 {avformat_free_context(mux); return nil}
	return mux
}
aac_frame :: proc(mux: ^AVFormatContext, packet: ^^AVPacket) -> bool {
	if avio_open_dyn_buf(&mux.pb) < 0 {return false}
	result := av_write_frame(mux, packet^)
	data: [^]u8
	size := avio_close_dyn_buf(mux.pb, &data)
	mux.pb = nil
	if result < 0 || size < 1 {av_freep(&data); return false}
	replacement := av_packet_alloc()
	if replacement == nil {av_freep(&data); return false}
	if av_packet_from_data(replacement, data, size) <
	   0 {av_freep(&data); av_packet_free(&replacement); return false}
	if av_packet_copy_props(replacement, packet^) < 0 {av_packet_free(&replacement); return false}
	replacement.stream_index = packet^.stream_index
	av_packet_free(packet)
	packet^ = replacement
	return true
}
