package main

import "./http"
import "./model"
import sb "./sponsorblock"
import yt "./youtube"
import "core:fmt"
import "core:strings"
import "core:sync/chan"
import "core:thread"
import sdl "vendor:sdl3"

Image_Request :: struct {
	source:         string,
	index:          int,
	target:         i32,
	page, playback: u32,
	cached:         bool,
}

Network_Request :: struct {
	kind:           enum {
		Search,
		Browse,
		Resolve,
		Use_Account,
		Account_Avatar,
		Login_Start,
		Login_Poll,
		Card_Action,
		Card_Membership,
		Watch_History,
	},
	page, playback: u32,
	position_ms:    f64,
	history_start:  f64,
	finished:       bool,
	start_paused:   bool,
	text:           string,
	continuation:   string,
	params, filter: string,
	index:          int,
	account:        u32,
	auth_token:     Auth_Token,
	action:         model.Card_Action,
}
Network_Result :: struct {
	kind:           enum {
		Catalog,
		Cover,
		Channel_Avatar,
		Stream,
		Account,
		Account_Avatar,
		Login_Code,
		Login_Waiting,
		Login_Authorized,
		Login_Error,
		Card_Action,
		Card_Membership,
	},
	page, playback: u32,
	position_ms:    f64,
	start_paused:   bool,
	index:          int,
	append:         bool,
	error:          yt.Error,
	catalog:        model.Catalog,
	// Cover pixels are decoded by the worker; only texture upload uses the UI.
	surface:        ^sdl.Surface,
	image_source:   string,
	stream:         yt.Stream,
	segments:       [dynamic]sb.Segment,
	login_code:     string,
	login_url:      string,
	login_message:  string,
	login_interval: int,
	auth_token:     Auth_Token,
	account:        u32,
	actions:        [dynamic]model.Card_Action,
}
network_requests: chan.Chan(Network_Request)
network_results: chan.Chan(Network_Result)
network_thread: ^thread.Thread
network_client: http.Client
network_event: sdl.EventType
page, playback: u32
search_loading: bool
resolving: bool
stream_width, stream_height: int
playback_requested_at: u64
playback_limits: [4]yt.Video_Limit
// Bumped whenever the catalog contents change, so fitted card labels rebuild.
catalog_revision: int

sponsor_segments: [dynamic]sb.Segment
pending_auth: Device_Auth
pending_auth_active: bool
account_revision: u32

free_network_request :: proc(request: ^Network_Request) {
	delete(request.text)
	delete(request.continuation)
	delete(request.params); delete(request.filter)
	model.card_action_destroy(&request.action)
	free_auth_token(&request.auth_token)
	request^ = {}
}

free_network_result :: proc(result: ^Network_Result) {
	model.catalog_destroy(&result.catalog)
	model.card_actions_destroy(&result.actions)
	sdl.DestroySurface(result.surface)
	delete(result.image_source)
	yt.stream_destroy(&result.stream)
	delete(result.segments)
	delete(result.login_code)
	delete(result.login_url)
	delete(result.login_message)
	free_auth_token(&result.auth_token)
	result^ = {}
}
post_network_result :: proc(result: Network_Result) -> bool {
	if !chan.send(network_results, result) {
		result := result
		free_network_result(&result)
		return false
	}
	event: sdl.Event
	event.type = network_event
	_ = sdl.PushEvent(&event)
	return true
}
network_stopping :: proc() -> bool {return chan.is_closed(network_requests)}

start_network :: proc() -> bool {
	success := false
	defer if !success {stop_network()}
	error: http.Error
	network_client, error = http.open()
	if error != nil {
		fmt.eprintln("network: HTTP client initialization failed:", error)
		return false
	}
	network_event = sdl.EventType(sdl.RegisterEvents(1))
	if u32(network_event) == 0 {
		fmt.eprintln("network: event registration failed:", sdl.GetError())
		return false
	}
	requests, req_error := chan.create(chan.Chan(Network_Request), 8, context.allocator)
	if req_error != .None {
		fmt.eprintln("network: request channel creation failed:", req_error)
		return false
	}
	network_requests = requests
	results, res_error := chan.create(chan.Chan(Network_Result), 8, context.allocator)
	if res_error != .None {
		fmt.eprintln("network: result channel creation failed:", res_error)
		return false
	}
	network_results = results
	if !start_image_loader() {
		fmt.eprintln("network: image worker creation failed")
		return false
	}
	network_thread = thread.create(network_main)
	if network_thread == nil {
		fmt.eprintln("network: worker thread creation failed")
		return false
	}
	if load_auth() {use_current_account()}
	thread.start(network_thread)
	success = true
	return true
}
stop_network :: proc() {
	_ = chan.close(network_requests)
	_ = chan.close(network_results)
	stop_image_loader()
	if network_thread != nil {thread.destroy(network_thread); network_thread = nil}
	for {
		request, ok := chan.try_recv(network_requests)
		if !ok {break}
		free_network_request(&request)
	}
	for {
		result, ok := chan.try_recv(network_results)
		if !ok {break}
		free_network_result(&result)
	}
	chan.destroy(network_requests)
	chan.destroy(network_results)
	network_requests = {}
	network_results = {}
	free_device_auth(&pending_auth)
	pending_auth_active = false
	http.close(&network_client)
	close_image_textures()
	close_account_avatars()
}
submit_network :: proc(request: Network_Request) -> bool {
	if chan.try_send(network_requests, request) {return true}
	// Reject overload without reordering account-dependent commands.
	request := request
	free_network_request(&request)
	return false
}

// Background reports must not discard foreground navigation or account commands.
queue_watch_history :: proc(
	id: string,
	start, position: f64,
	account, generation: u32,
	finished: bool,
) -> bool {
	return submit_network(
		{
			kind = .Watch_History,
			text = strings.clone(id),
			account = account,
			playback = generation,
			history_start = start,
			position_ms = position * 1000,
			finished = finished,
		},
	)
}

resolve_selected :: proc(position_ms: f64 = 0, start_paused: bool = false) {
	if selected < 0 || selected >= len(catalog.videos) {return}
	clear_player_channel()
	playback += 1
	playback_requested_at = sdl.GetTicks()
	resolving = true
	browsing = false
	loaded = false
	stream_width, stream_height = 0, 0
	notice = ""
	dirty = true
	delete(sponsor_segments); sponsor_segments = nil
	if !submit_network(
		{
			kind = .Resolve,
			page = page,
			playback = playback,
			position_ms = position_ms,
			start_paused = start_paused,
			text = strings.clone(catalog.videos[selected].id),
		},
	) {
		resolving = false; browsing = true; show_notice("Network unavailable")
	}
}

apply_stream :: proc(renderer: ^sdl.Renderer, result: ^Network_Result) {
	if browsing || return_to_grid || !resolving || result.playback != playback {return}
	resolving = false
	if result.error != .None {
		browsing = true
		show_notice(
			result.error == .No_Direct_Stream ? "YouTube did not provide a supported direct stream" : "Could not load video",
		)
	} else {
		stream_width, stream_height = result.stream.width, result.stream.height
		delete(sponsor_segments)
		sponsor_segments = result.segments
		result.segments = nil
		if result.stream.title != "" {
			if result.stream.title != catalog.videos[selected].title {labels_release()}
			delete(catalog.videos[selected].title)
			catalog.videos[selected].title = result.stream.title
			result.stream.title = ""
		}
		player_channel_id = result.stream.channel_id
		result.stream.channel_id = ""
		fmt.printf("{{\"event\":\"stream\",\"client\":\"%s\"}}\n", result.stream.client)
		load_video(result.stream, renderer, result.position_ms, result.start_paused)
		if player_channel_id != "" {
			player_avatar := [1]Image_Request {
				{
					source = strings.clone(player_channel_id),
					index = -1,
					target = 2 * PLAYER_AVATAR_SIZE,
					page = page,
					playback = playback,
				},
			}
			queue_images(player_avatar[:], false)
		}
		show_player_controls()
	}
	dirty = true
}

poll_network :: proc(renderer: ^sdl.Renderer) {
	// Bound image uploads per frame so input is still serviced during loading.
	for _ in 0 ..< 2 {
		result, ok := chan.try_recv(network_results)
		if !ok {break}
		defer free_network_result(&result)
		#partial switch result.kind {
		case .Account_Avatar,
		     .Account,
		     .Login_Code,
		     .Login_Waiting,
		     .Login_Authorized,
		     .Login_Error:
			apply_auth_result(renderer, &result)
		case:
			if result.page != page {continue}
			#partial switch result.kind {
			case .Card_Action, .Card_Membership:
				apply_card_result(&result)
			case .Catalog:
				apply_catalog(&result)
			case .Cover, .Channel_Avatar:
				apply_image(renderer, &result)
			case .Stream:
				apply_stream(renderer, &result)
			}
		}
	}
}
