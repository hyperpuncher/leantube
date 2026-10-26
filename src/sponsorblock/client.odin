package sponsorblock

import "../http"
import "../model"
import "core:encoding/json"
import "core:fmt"
import "core:math"

Segment :: struct {
	start_ms, end_ms, video_duration_ms: f64,
	skipped:                             bool,
}

// Use the existing OpenSSL library: core SHA-256 currently emits unsupported
// ARM SHA instructions when compiled for the B9 Cortex-A9 target.
foreign import crypto "system:crypto"
foreign crypto {
	SHA256 :: proc(data: rawptr, count: uint, digest: ^u8) -> ^u8 ---
}

// The documented four-character prefix avoids sending the exact video ID.
// No submissions, votes, or skip-count requests are sent.
endpoint :: proc(id: string) -> string {
	digest: [32]u8
	SHA256(raw_data(id), uint(len(id)), &digest[0])
	return fmt.aprintf("https://sponsor.ajay.app/api/skipSegments/%02x%02x", digest[0], digest[1])
}

parse :: proc(data, id: string) -> (segments: [dynamic]Segment, valid: bool) {
	value, error := json.parse(data)
	if error != .None {return nil, false}
	defer json.destroy_value(value)
	videos, root_valid := value.(json.Array)
	if !root_valid {return nil, false}
	for video in videos {
		entry, entry_valid := video.(json.Object)
		if !entry_valid {continue}
		video_id, _ := entry["videoID"].(json.String)
		if string(video_id) != id {continue}
		items, _ := entry["segments"].(json.Array)
		for item in items {
			object, item_valid := item.(json.Object)
			if !item_valid {continue}
			category, _ := object["category"].(json.String)
			action, _ := object["actionType"].(json.String)
			if category != "sponsor" || action != "skip" {continue}
			times, _ := object["segment"].(json.Array)
			if len(times) != 2 {continue}
			start, a := model.number(times[0])
			end, b := model.number(times[1])
			length, _ := model.number(object["videoDuration"])
			if !a || !b || start < 0 || end <= start {continue}
			append(
				&segments,
				Segment {
					start_ms = start * 1000,
					end_ms = end * 1000,
					video_duration_ms = length * 1000,
				},
			)
		}
	}
	return segments, true
}

fetch :: proc(client: ^http.Client, id: string) -> (segments: [dynamic]Segment) {
	url := endpoint(id)
	defer delete(url)
	response, error := http.request(client, url, timeout_ms = 2000)
	if error != nil {return nil}
	defer delete(response.body)
	if response.status != 200 {return nil} 	// 404 means that there are no segments.
	segments, _ = parse(string(response.body[:]), id)
	return
}

// Shared by the skip action and its timeline markers.
can_skip :: proc(segment: Segment, duration_ms: f64) -> bool {
	return(
		!segment.skipped &&
		segment.start_ms >= 0 &&
		segment.end_ms > segment.start_ms &&
		segment.end_ms <= duration_ms &&
		(segment.video_duration_ms <= 0 ||
				math.abs(segment.video_duration_ms - duration_ms) <= 1000) \
	)
}

// Skip an overlapping group once per playback. This avoids repeating a seek
// on stale media notifications and lets a user intentionally rewind to it.
skip_target :: proc(segments: []Segment, position_ms, duration_ms: f64) -> f64 {
	target := position_ms
	for {
		before := target
		for segment in segments {
			if !can_skip(segment, duration_ms) {continue}
			if segment.start_ms <= target &&
			   segment.end_ms > position_ms {target = max(target, segment.end_ms)}
		}
		if target == before {break}
	}
	return target > position_ms ? target : -1
}
mark_skipped :: proc(segments: []Segment, from_ms, to_ms: f64) {
	for &segment in segments {
		if segment.start_ms <= to_ms && segment.end_ms > from_ms {segment.skipped = true}
	}
}
