package main

import http "../../src/http"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import curl "vendor:curl"

main :: proc() {
	passed := false
	defer if !passed {os.exit(1)}
	client, error := http.open()
	assert(error == nil)
	defer http.close(&client)
	fmt.println("native HTTP library:", string(curl.version()))
	body := `{"context":{"client":{"clientName":"ANDROID","clientVersion":"21.26.364","androidSdkVersion":30,"osName":"Android","osVersion":"11","hl":"en"}},"videoId":"aqz-KE-bpKQ","contentCheckOk":true,"racyCheckOk":true}`
	response, request_error := http.request(
		&client,
		"https://www.youtube.com/youtubei/v1/player",
		body,
		{
			"Content-Type: application/json",
			"X-Youtube-Client-Name: 3",
			"X-Youtube-Client-Version: 21.26.364",
			"User-Agent: com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip",
		},
	)
	defer delete(response.body)
	if request_error != nil {fmt.eprintln("YouTube transport failed:", request_error); return}
	assert(response.status == 200)
	info: struct {
		playabilityStatus: struct {
			status: string,
		},
	}
	defer delete(info.playabilityStatus.status)
	assert(json.unmarshal(response.body[:], &info) == nil)
	assert(info.playabilityStatus.status != "")
	fmt.printf(
		"YouTube HTTPS: status=%d bytes=%d playability=%s\n",
		response.status,
		len(response.body),
		info.playabilityStatus.status,
	)
	// SHA-256 prefix for the same public test video, not its complete ID.
	segments, segments_error := http.request(
		&client,
		"https://sponsor.ajay.app/api/skipSegments/671e?categories=%5B%22sponsor%22%5D",
	)
	defer delete(segments.body)
	if segments_error !=
	   nil {fmt.eprintln("SponsorBlock transport failed:", segments_error); return}
	assert(segments.status == 200 || segments.status == 404)
	fmt.printf("SponsorBlock HTTPS: status=%d bytes=%d\n", segments.status, len(segments.body))
	passed = true
}
