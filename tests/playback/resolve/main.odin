package main

import "../../../src/http"
import "../../../src/model"
import yt "../../../src/youtube"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

// Save the player response on the host. Do not print media URLs or response data.
main :: proc() {
	assert(len(os.args) == 3, "expected a video ID file and a new output file")
	assert(!os.exists(os.args[2]), "use a new private output file")
	id_bytes, read_error := os.read_entire_file(os.args[1], context.allocator)
	assert(read_error == nil, "could not read the video ID")
	defer delete(id_bytes)
	id := strings.trim_space(string(id_bytes))
	assert(yt.video_id_valid(id), "invalid video ID")
	client, client_error := http.open()
	assert(client_error == nil, "HTTPS setup failed")
	defer http.close(&client)
	catalog, search_error, visitor := yt.search(&client, "garden")
	assert(search_error == .None && visitor != "", "anonymous session request failed")
	defer model.catalog_destroy(&catalog)
	defer delete(visitor)
	payload := struct {
		ctx:                         struct {
			client: yt.Client_Context,
		} `json:"context"`,
		videoId:                     string,
		contentCheckOk, racyCheckOk: bool,
	} {
		ctx = {
			client = {
				clientName = "VISIONOS",
				clientVersion = yt.VISIONOS_VERSION,
				hl = "en",
				gl = "US",
				deviceMake = "Apple",
				deviceModel = "RealityDevice17,1",
				userAgent = yt.VISIONOS_AGENT,
				osName = "visionOS",
				osVersion = "26.5.23O471",
				timeZone = "UTC",
				visitorData = visitor,
			},
		},
		videoId = id,
		contentCheckOk = true,
		racyCheckOk = true,
	}
	body, marshal_error := json.marshal(payload)
	assert(marshal_error == nil, "could not encode the player request")
	defer delete(body)
	response, request_error := yt.api_post(&client, "player", body, .VisionOS)
	assert(request_error == .None, "player request failed")
	defer delete(response.body)
	value, parse_error := json.parse(string(response.body[:]))
	assert(parse_error == .None, "invalid player response")
	defer json.destroy_value(value)
	status, _ := yt.field(yt.field(value, "playabilityStatus"), "status").(json.String)
	assert(status == "OK", "the player response is not playable")
	assert(
		os.write_entire_file(os.args[2], response.body[:], {.Read_User, .Write_User}) == nil,
		"could not save the private player response",
	)
	fmt.println("private player response saved on the host")
}
