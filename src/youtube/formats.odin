package youtube

import "core:encoding/json"
import "core:strings"

Video_Limit :: struct {
	codec:              string,
	width, height, fps: int,
}

video_codec :: proc(mime: string) -> string {
	if !strings.has_prefix(mime, "video/") {return ""}
	for pair in ([][2]string{{"av01", "av1"}, {"vp09", "vp9"}, {"vp9", "vp9"}, {"avc1", "h264"}, {"hvc1", "hevc"}, {"hev1", "hevc"}}) {
		if strings.contains(mime, pair[0]) {return pair[1]}
	}
	return ""
}

supported_video :: proc(codec: string, width, height, fps: int, limits: []Video_Limit) -> bool {
	if codec == "" || width <= 0 || height <= 0 || fps <= 0 {return false}
	if limits == nil {return true} 	// Host tools do not have LG capabilities.
	for limit in limits {
		if limit.codec == codec {
			return width <= limit.width && height <= limit.height && fps <= limit.fps
		}
	}
	return false
}

// Return separate direct sources. Returned strings remain owned by the caller.
parse_player :: proc(data: string, limits: []Video_Limit = nil) -> (stream: Stream, error: Error) {
	value, err := json.parse(data)
	if err != .None {return {}, .Invalid_Response}
	defer json.destroy_value(value)
	status, _ := field(field(value, "playabilityStatus"), "status").(json.String)
	if status != "OK" {return {}, .Unavailable}
	adaptive, _ := field(field(value, "streamingData"), "adaptiveFormats").(json.Array)
	combined, _ := field(field(value, "streamingData"), "formats").(json.Array)
	audio := original_audio(adaptive)
	if audio.url == "" {
		// Some responses expose AAC only in a combined stream. Read its audio
		// without reducing the independently selected video quality.
		for format in combined {
			mime, _ := field(format, "mimeType").(json.String)
			url, _ := field(format, "url").(json.String)
			if strings.has_prefix(string(url), "https://") &&
			   strings.contains(string(mime), "mp4a.40.2") {
				audio.url = strings.clone(string(url)); break
			}
		}
	}
	if audio.url == "" {return {}, .No_Direct_Stream}
	best_area, best_fps, best_hdr, best_bitrate := f64(0), f64(0), false, f64(0)
	for formats in ([]json.Array{adaptive, combined}) {
		for format in formats {
			url, _ := field(format, "url").(json.String)
			mime, _ := field(format, "mimeType").(json.String)
			width, _ := numeric(field(format, "width"))
			height, _ := numeric(field(format, "height"))
			fps, _ := numeric(field(format, "fps"))
			bitrate, _ := numeric(field(format, "bitrate"))
			codec := video_codec(string(mime))
			drm, _ := field(format, "drmFamilies").(json.Array)
			if len(drm) > 0 ||
			   !strings.has_prefix(string(url), "https://") ||
			   !supported_video(codec, int(width), int(height), int(fps), limits) {continue}
			transfer, _ := field(
				field(format, "colorInfo"),
				"transferCharacteristics",
			).(json.String)
			transfer_name := strings.trim_prefix(
				string(transfer),
				"COLOR_TRANSFER_CHARACTERISTICS_",
			)
			hdr := transfer_name == "SMPTEST2084" || transfer_name == "ARIB_STD_B67"
			area := width * height
			better :=
				area > best_area ||
				(area == best_area &&
						(fps > best_fps ||
								(fps == best_fps &&
										((hdr && !best_hdr) ||
												(hdr == best_hdr && bitrate > best_bitrate)))))
			if !better {continue}
			delete(stream.url)
			stream.url = strings.clone(string(url))
			stream.width, stream.height = int(width), int(height)
			best_area, best_fps, best_hdr, best_bitrate = area, fps, hdr, bitrate
		}
	}
	if stream.url == "" {delete(audio.url); return {}, .No_Direct_Stream}
	stream.audio_url = audio.url
	channel_id, _ := field(field(value, "videoDetails"), "channelId").(json.String)
	stream.channel_id = strings.clone(string(channel_id))
	title, _ := field(field(value, "videoDetails"), "title").(json.String)
	stream.title = strings.clone(string(title))
	seconds, _ := numeric(field(field(value, "videoDetails"), "lengthSeconds"))
	if seconds > 0 {stream.duration_ms = seconds * 1000}
	return
}
