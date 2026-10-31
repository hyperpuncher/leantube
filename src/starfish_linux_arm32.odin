package main

import reader "./playback"
import "base:runtime"
import "core:c"
import queue "core:container/queue"
import "core:fmt"
import "core:strings"
import "core:sync"
import "core:time"

// The C++ type stays opaque. Only the upstream C interface crosses this boundary.
Starfish :: struct {}
Starfish_Callback :: #type proc "c" (kind: c.int, value: i64, text: cstring, user: rawptr)
foreign import starfish "system:playerAPIs_C"
foreign starfish {
	@(link_name = "StarfishMediaAPIs_create")
	sf_create :: proc(_: cstring) -> ^Starfish ---
	@(link_name = "StarfishMediaAPIs_destroy")
	sf_destroy :: proc(_: ^Starfish) ---
	@(link_name = "StarfishMediaAPIs_getMediaID")
	sf_media_id :: proc(_: ^Starfish) -> cstring ---
	@(link_name = "StarfishMediaAPIs_load")
	sf_load :: proc(_: ^Starfish, _: cstring, _: Starfish_Callback, _: rawptr) -> bool ---
	@(link_name = "StarfishMediaAPIs_feed")
	sf_feed :: proc(_: ^Starfish, _: cstring, _: [^]u8, _: c.size_t) -> bool ---
	@(link_name = "StarfishMediaAPIs_notifyForeground")
	sf_foreground :: proc(_: ^Starfish) -> bool ---
	@(link_name = "StarfishMediaAPIs_play")
	sf_play :: proc(_: ^Starfish) -> bool ---
	@(link_name = "StarfishMediaAPIs_pause")
	sf_pause :: proc(_: ^Starfish) -> bool ---
	@(link_name = "StarfishMediaAPIs_pushEOS")
	sf_eos :: proc(_: ^Starfish) -> bool ---
	@(link_name = "StarfishMediaAPIs_setPlayRate")
	sf_rate :: proc(_: ^Starfish, _: cstring) -> bool ---
	@(link_name = "StarfishMediaAPIs_videoLimits")
	sf_video_limits :: proc(_: cstring, _: ^c.int, _: ^c.int, _: ^c.int) -> bool ---
	@(link_name = "StarfishMediaAPIs_unload")
	sf_unload :: proc(_: ^Starfish) -> bool ---
}
Decoder_Status :: struct {
	loaded, unloaded, error, playing, ended: i32,
	presentation_updates, dropped, frame_ns: i64,
}
decoder_callback :: proc "c" (kind: c.int, value: i64, text: cstring, user: rawptr) {
	context = runtime.default_context()
	s := cast(^Decoder_Status)user
	// Never log event strings, load requests, or packet pointers.
	switch kind {
	case 0:
		sync.atomic_store(&s.frame_ns, value); sync.atomic_add(&s.presentation_updates, 1)
	case 0x12, 0x13:
		sync.atomic_store(&s.error, i32(value == 0 ? -1 : value))
	case 0x16:
		sync.atomic_store(&s.loaded, 1)
	case 0x17:
		sync.atomic_store(&s.unloaded, 1)
	case 0x1a:
		sync.atomic_store(&s.playing, 1)
	case 0x1b:
		sync.atomic_store(&s.playing, 0)
	case 0x1c:
		sync.atomic_store(&s.ended, 1)
	case 0x30:
		sync.atomic_add(&s.dropped, 1)
	}
}
decoder_close :: proc(api: ^Starfish, status: ^Decoder_Status) -> bool {
	accepted := sf_unload(api)
	start := time.tick_now()
	for sync.atomic_load(&status.unloaded) == 0 && reader.seconds_since(start) < 3 {
		poll_services()
		time.sleep(5 * time.Millisecond)
	}
	complete := sync.atomic_load(&status.unloaded) != 0
	fmt.printf(
		"{{\"event\":\"decoder_unload\",\"accepted\":%v,\"completed\":%v}}\n",
		accepted,
		complete,
	)
	release_display()
	// A missing completion is fatal to this diagnostic. Keep callback storage
	// live until process exit rather than reuse a possibly live native session.
	if !complete {running = false; return false}
	sf_destroy(api)
	free(status)
	return true
}
decoder_open :: proc(
	v, a: ^reader.Track,
	target: f64,
) -> (
	api: ^Starfish,
	status: ^Decoder_Status,
) {
	config, valid := reader.aac_config(a.audio_config)
	if !a.audio_config_valid || !valid {return}
	api = sf_create(nil)
	if api == nil {return}
	status = new(Decoder_Status)
	status.frame_ns = -1
	id := string(sf_media_id(api))
	hdr := ""
	if v.color_transfer == 16 {hdr = ",\"hdrType\":\"HDR10\""}
	if v.color_transfer == 18 {hdr = ",\"hdrType\":\"HLG\""}
	metadata := fmt.aprintf(
		`{{"context":"%s","content":"movie","video":{{"width":%d,"height":%d,"frameRate":%.6f,"scanType":"VIDEO_PROGRESSIVE","path":"network"%s}}}}`,
		id,
		v.width,
		v.height,
		v.fps,
		hdr,
	)
	defer delete(metadata)
	if !attach_display(
		APP_ID,
		id,
		metadata,
		10,
		true,
	) {release_display(); sf_destroy(api); free(status); return nil, nil}
	sf_foreground(api)
	payload := fmt.aprintf(
		`{{"args":[{{"mediaTransportType":"BUFFERSTREAM","option":{{"appId":"%s","queryPosition":false,"externalStreamingInfo":{{"contents":{{"format":"RAW","provider":"Chrome","codec":{{"video":"%s","audio":"AAC"}},"esInfo":{{"pauseAtDecodeTime":false,"seperatedPTS":true,"ptsToDecode":%d,"videoWidth":%d,"videoHeight":%d,"videoFpsValue":%d,"videoFpsScale":%d}},"aacInfo":{{"channels":%d,"format":"adts","frequency":%.3f,"profile":2}}}},"restartStreaming":false,"totalStreamSize":256,"bufferingCtrInfo":{{"preBufferByte":0,"bufferMinLevel":0,"bufferMaxLevel":0,"qBufferLevelAudio":0,"qBufferLevelVideo":0,"srcBufferLevelAudio":{{"minimum":1024,"maximum":1048576}},"srcBufferLevelVideo":{{"minimum":1024,"maximum":8388608}}}}}},"adaptiveStreaming":{{"audioOnly":false,"maxWidth":%d,"maxHeight":%d,"maxFrameRate":%.6f}}}}}}]}}`,
		APP_ID,
		native_video_codec(v.codec),
		i64(target * 1e9),
		v.width,
		v.height,
		v.frame_rate.num,
		v.frame_rate.den,
		config.channels,
		f64(config.rate) / 1000,
		v.width,
		v.height,
		v.fps,
	)
	body := strings.clone_to_cstring(payload)
	defer delete(payload); defer delete(body)
	if !sf_load(api, body, decoder_callback, status) {decoder_close(api, status); return nil, nil}
	fmt.printf(
		"{{\"event\":\"decoder_load\",\"codec\":\"%s\",\"width\":%d,\"height\":%d,\"fps\":%.6f,\"transfer\":%d,\"audio_rate\":%d,\"audio_channels\":%d}}\n",
		v.codec,
		v.width,
		v.height,
		v.fps,
		v.color_transfer,
		config.rate,
		config.channels,
	)
	return
}
decoder_feed :: proc(api: ^Starfish, t: ^reader.Track, limit: f64) -> bool {
	sync.mutex_lock(&t.mutex)
	defer sync.mutex_unlock(&t.mutex)
	for queue.len(t.packets) > 0 && queue.front(&t.packets).pts <= limit {
		p := queue.front(&t.packets)
		payload := fmt.aprintf(
			`{{"bufferAddr":"0x%x","bufferSize":%d,"pts":%d,"esData":%d}}`,
			uintptr(p.packet.data),
			p.packet.size,
			i64(p.pts * 1e9),
			t.media_type == 0 ? 1 : 2,
		)
		body := strings.clone_to_cstring(payload)
		reply: [256]u8
		ok := sf_feed(api, body, raw_data(reply[:]), len(reply))
		delete(body); delete(payload)
		if !ok {return false}
		text := string(cstring(raw_data(reply[:])))
		if strings.contains(text, "BufferFull") || strings.contains(text, "Pending") {break}
		if !strings.contains(text, "Ok") {return false}
		p = queue.pop_front(&t.packets)
		t.queued_bytes -= i64(p.packet.size)
		reader.av_packet_free(&p.packet)
	}
	sync.cond_signal(&t.changed)
	return true
}
