package youtube

import "../http"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"

// Private, short-lived HLS files. They contain signed child URLs, so they stay
// mode 0600 and are removed when playback stops.
LOCAL_HLS_PATH :: "/tmp/leantube-master.m3u8"
LOCAL_AUDIO_HLS_PATH :: "/tmp/leantube-audio.m3u8"
LOCAL_AUDIO_GROUP :: "leantube-audio"

attribute :: proc(line, key: string) -> string {
	needle := strings.concatenate({key, "="})
	defer delete(needle)
	start := strings.index(line, needle)
	if start < 0 {return ""}
	start += len(key) + 1
	if start < len(line) && line[start] == '"' {
		start += 1
		end := strings.index(line[start:], `"`)
		if end < 0 {return ""}
		return line[start:start + end]
	}
	end := strings.index(line[start:], ",")
	if end < 0 {return line[start:]}
	return line[start:start + end]
}

resolution_height :: proc(resolution: string) -> int {
	x := strings.index_byte(resolution, 'x')
	if x <= 0 {return 0}
	height: int
	for ch in resolution[x + 1:] {
		if ch < '0' || ch > '9' {break}
		height = height * 10 + int(ch - '0')
	}
	return height
}

// Remove one attribute and exactly one separator, without merging neighbors.
without_attribute :: proc(line, key: string) -> string {
	needle := strings.concatenate({key, "="})
	defer delete(needle)
	key_start := strings.index(line, needle)
	if key_start < 0 {return line}
	end := key_start
	quoted := false
	for end < len(line) {
		if line[end] == '"' {quoted = !quoted}
		if !quoted && line[end] == ',' {break}
		end += 1
	}
	start := key_start
	if start > 0 && line[start - 1] == ',' {
		start -= 1
	} else if end < len(line) {
		end += 1
	}
	result, _ := strings.concatenate({line[:start], line[end:]})
	return result
}

write_private :: proc(path, text: string) -> bool {
	_ = os.remove(path)
	file, open_error := os.open(
		path,
		{.Create, .Write, .Trunc},
		os.Permissions{.Read_User, .Write_User},
	)
	if open_error != nil {return false}
	defer os.close(file)
	written, write_error := os.write_string(file, text)
	return write_error == nil && written == len(text)
}

Sidx_Segment :: struct {
	duration_ticks: u32,
	size:           u32,
}

u32be :: proc(data: []u8, offset: int) -> (u32, bool) {
	if offset < 0 || offset + 4 > len(data) {return 0, false}
	return u32(data[offset]) << 24 |
		u32(data[offset + 1]) << 16 |
		u32(data[offset + 2]) << 8 |
		u32(data[offset + 3]),
		true
}

parse_sidx :: proc(
	data: []u8,
) -> (
	segments: []Sidx_Segment,
	timescale: u32,
	first_offset: u32,
	ok: bool,
) {
	box_size, size_ok := u32be(data, 0)
	if !size_ok || int(box_size) > len(data) || box_size < 24 {return}
	if string(data[4:8]) != "sidx" {return}
	version := data[8]
	cursor := 12
	_, id_ok := u32be(data, cursor)
	if !id_ok {return}
	cursor += 4
	timescale, ok = u32be(data, cursor)
	if !ok || timescale == 0 {return}
	cursor += 4
	if version == 0 {
		_, ok = u32be(data, cursor)
		if !ok {return}
		cursor += 4
		first_offset, ok = u32be(data, cursor)
		if !ok {return}
		cursor += 4
	} else if version == 1 {
		cursor += 8
		first_offset, ok = u32be(data, cursor + 4)
		if !ok {return}
		cursor += 8
	} else {
		return
	}
	if cursor + 4 > int(box_size) {return}
	count := int(data[cursor + 2]) << 8 | int(data[cursor + 3])
	cursor += 4
	if count <= 0 || cursor + count * 12 > int(box_size) {return}
	segments = make([]Sidx_Segment, count)
	for index in 0 ..< count {
		reference, reference_ok := u32be(data, cursor)
		duration, duration_ok := u32be(data, cursor + 4)
		if !reference_ok || !duration_ok {
			delete(segments)
			return nil, 0, 0, false
		}
		segments[index] = {
			duration_ticks = duration,
			size           = reference & 0x7fffffff,
		}
		cursor += 12
	}
	ok = true
	return
}

fetch_range :: proc(client: ^http.Client, url: string, start, end: int) -> ([]u8, bool) {
	if start < 0 || end < start {return nil, false}
	header := fmt.aprintf("Range: bytes=%d-%d", start, end)
	defer delete(header)
	response, request_error := http.request(client, url, "", []string{header}, timeout_ms = 3000)
	if request_error != nil {return nil, false}
	defer delete(response.body)
	result := make([]u8, end - start + 1)
	if response.status == 206 {
		if len(response.body) < len(result) {delete(result); return nil, false}
		copy(result, response.body[:len(result)])
		return result, true
	}
	if response.status != 200 || len(response.body) <= end {delete(result); return nil, false}
	copy(result, response.body[start:end + 1])
	return result, true
}

// Force the highest HLS variant and add the original AAC track as a local
// audio rendition. Returns false and leaves the original URL untouched on any
// parse or write failure.
localize_hls :: proc(client: ^http.Client, stream: ^Stream) -> bool {
	response, request_error := http.request(client, stream.url, timeout_ms = 3000)
	if request_error != nil {return false}
	defer delete(response.body)
	if response.status != 200 {return false}
	master := string(response.body[:])
	lines := strings.split(master, "\n")
	defer delete(lines)
	best, best_height := -1, 0
	for line, index in lines {
		if !strings.has_prefix(line, "#EXT-X-STREAM-INF:") || index + 1 >= len(lines) {continue}
		height := resolution_height(attribute(line, "RESOLUTION"))
		if height > 2160 {continue}
		if height > best_height {best, best_height = index, height}
	}
	if best < 0 {return false}
	variant := lines[best]
	variant_uri := strings.trim_space(lines[best + 1])
	if !strings.has_prefix(variant_uri, "https://") {return false}
	has_audio := false
	init_len := stream.audio_init_end + 1
	if stream.audio_url != "" && init_len > 0 && stream.audio_index_end >= stream.audio_init_end {
		index_start := init_len
		index_end := stream.audio_index_end
		if sidx, fetched := fetch_range(client, stream.audio_url, index_start, index_end);
		   fetched {
			defer delete(sidx)
			segments, timescale, first_offset, parsed := parse_sidx(sidx)
			defer delete(segments)
			if parsed && timescale > 0 && len(segments) > 0 {
				audio := strings.builder_make()
				defer strings.builder_destroy(&audio)
				target := 0
				for segment in segments {
					seconds := int(math.ceil(f64(segment.duration_ticks) / f64(timescale)))
					if seconds > target {target = seconds}
				}
				strings.write_string(&audio, "#EXTM3U\n#EXT-X-VERSION:7\n")
				fmt.sbprintf(&audio, "#EXT-X-TARGETDURATION:%d\n", target)
				strings.write_string(&audio, "#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-PLAYLIST-TYPE:VOD\n")
				fmt.sbprintf(
					&audio,
					"#EXT-X-MAP:URI=\"%s\",BYTERANGE=\"%d@0\"\n",
					stream.audio_url,
					init_len,
				)
				offset := index_end + 1 + int(first_offset)
				for segment in segments {
					duration := f64(segment.duration_ticks) / f64(timescale)
					fmt.sbprintf(&audio, "#EXTINF:%.3f,\n", duration)
					fmt.sbprintf(
						&audio,
						"#EXT-X-BYTERANGE:%d@%d\n%s\n",
						segment.size,
						offset,
						stream.audio_url,
					)
					offset += int(segment.size)
				}
				strings.write_string(&audio, "#EXT-X-ENDLIST\n")
				has_audio = write_private(LOCAL_AUDIO_HLS_PATH, strings.to_string(audio))
			}
		}
	}
	if !has_audio {_ = os.remove(LOCAL_AUDIO_HLS_PATH)}
	if attribute(variant, "AUDIO") != "" {variant = without_attribute(variant, "AUDIO")}
	if attribute(variant, "SUBTITLES") != "" {variant = without_attribute(variant, "SUBTITLES")}
	variant = strings.trim_space(variant)
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "#EXTM3U\n")
	for line in lines {
		if strings.has_prefix(line, "#EXT-X-VERSION") ||
		   strings.has_prefix(line, "#EXT-X-INDEPENDENT-SEGMENTS") {
			strings.write_string(&builder, line)
			strings.write_byte(&builder, '\n')
		}
	}
	if has_audio {
		strings.write_string(
			&builder,
			`#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="` +
			LOCAL_AUDIO_GROUP +
			`",NAME="Original",DEFAULT=YES,AUTOSELECT=YES,URI="leantube-audio.m3u8"` +
			"\n",
		)
	}
	strings.write_string(&builder, variant)
	if has_audio {
		strings.write_string(&builder, `,AUDIO="` + LOCAL_AUDIO_GROUP + `"`)
	}
	strings.write_byte(&builder, '\n')
	strings.write_string(&builder, variant_uri)
	strings.write_byte(&builder, '\n')
	if !write_private(LOCAL_HLS_PATH, strings.to_string(builder)) {return false}
	fmt.printf("private hls master: %dp audio=%v\n", best_height, has_audio)
	delete(stream.url)
	stream.url = strings.clone("file://" + LOCAL_HLS_PATH)
	return true
}

remove_local_hls :: proc() {
	_ = os.remove(LOCAL_HLS_PATH)
	_ = os.remove(LOCAL_AUDIO_HLS_PATH)
}
