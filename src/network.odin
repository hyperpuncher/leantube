package main

import clay "../vendor/clay"
import "./http"
import "./model"
import sb "./sponsorblock"
import yt "./youtube"
import "core:fmt"
import "core:strings"
import "core:sync/chan"
import "core:thread"
import sdl "vendor:sdl3"
import img "vendor:sdl3/image"

Network_Request :: struct {
	kind:           enum {
		Search,
		Resolve,
		Account,
		Avatar,
		Login_Start,
		Login_Poll,
	},
	page, playback: u32,
	text:           string,
}
Network_Result :: struct {
	kind:           enum {
		Catalog,
		Cover,
		Stream,
		Segments,
		Account,
		Avatar,
		Login_Code,
		Login_Waiting,
		Login_Authorized,
		Login_Error,
	},
	page, playback: u32,
	index:          int,
	error:          yt.Error,
	catalog:        model.Catalog,
	bytes:          [dynamic]u8,
	stream:         yt.Stream,
	segments:       [dynamic]sb.Segment,
	login_code:     string,
	login_url:      string,
	login_message:  string,
	login_name:     string,
	login_avatar:   string,
	login_interval: int,
	auth_token:     Auth_Token,
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
sponsor_segments: [dynamic]sb.Segment
pending_auth: Device_Auth
pending_auth_active: bool

free_network_result :: proc(result: ^Network_Result) {
	model.catalog_destroy(&result.catalog)
	delete(result.bytes)
	delete(result.stream.url)
	delete(result.stream.audio_url)
	delete(result.segments)
	delete(result.login_code)
	delete(result.login_url)
	delete(result.login_message)
	delete(result.login_name)
	delete(result.login_avatar)
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

network_main :: proc(_: ^thread.Thread) {
	ids: [model.MAX_VIDEOS][11]u8
	count, next: int
	cover_page: u32
	visitor_data: string
	defer delete(visitor_data)
	for !chan.is_closed(network_requests) {
		request, ready := chan.try_recv(network_requests)
		if !ready && next < count {
			index := next
			next += 1
			bytes := yt.thumbnail(&network_client, string(ids[index][:]), network_stopping)
			if len(bytes) > 0 {
				if !post_network_result(
					{kind = .Cover, page = cover_page, index = index, bytes = bytes},
				) {return}
			}
			continue
		}
		if !ready {request, ready = chan.recv(network_requests)}
		if !ready {return}
		defer delete(request.text)
		switch request.kind {
		case .Account:
			name, avatar_url := yt.account_info(&network_client)
			avatar: [dynamic]u8
			if avatar_url != "" {
				response, error := yt.fetch_thumbnail(&network_client, avatar_url)
				if error == nil && response.status == 200 {
					avatar = response.body
				} else {
					delete(response.body)
				}
			}
			if !post_network_result(
				{kind = .Account, login_name = name, login_avatar = avatar_url, bytes = avatar},
			) {return}
		case .Avatar:
			response, error := yt.fetch_thumbnail(&network_client, request.text)
			if error != nil || response.status != 200 {
				delete(response.body)
				continue
			}
			if !post_network_result({kind = .Avatar, bytes = response.body}) {return}
		case .Search:
			catalog, error, visitor := yt.search(&network_client, request.text)
			delete(visitor_data)
			visitor_data = visitor
			cover_page = request.page
			count, next = len(catalog.videos), 0
			for video, i in catalog.videos {copy(ids[i][:], transmute([]u8)video.id)}
			if !post_network_result(
				{kind = .Catalog, page = request.page, error = error, catalog = catalog},
			) {return}
		case .Login_Start:
			if pending_auth_active {
				free_device_auth(&pending_auth)
				pending_auth_active = false
			}
			device, ok := begin_login(&network_client)
			if !ok {
				if !post_network_result(
					{
						kind = .Login_Error,
						login_message = strings.clone("could not start sign-in"),
					},
				) {return}
				continue
			}
			pending_auth = device
			pending_auth_active = true
			if !post_network_result(
				{
					kind = .Login_Code,
					login_code = strings.clone(device.user_code),
					login_url = strings.clone(device.verification_url),
					login_interval = device.interval,
				},
			) {return}
		case .Login_Poll:
			if !pending_auth_active {
				if !post_network_result(
					{kind = .Login_Error, login_message = strings.clone("sign-in expired")},
				) {return}
				continue
			}
			token, status, message := poll_login(&network_client, pending_auth)
			switch status {
			case .Authorized:
				free_device_auth(&pending_auth)
				pending_auth_active = false
				yt.set_access_token(token.access_token)
				token.name, token.avatar_url = yt.account_info(&network_client)
				avatar: [dynamic]u8
				if token.avatar_url != "" {
					response, error := yt.fetch_thumbnail(&network_client, token.avatar_url)
					if error == nil && response.status == 200 {
						avatar = response.body
					} else {
						delete(response.body)
					}
				}
				if !post_network_result(
					{kind = .Login_Authorized, bytes = avatar, auth_token = token},
				) {return}
			case .Pending, .Slow_Down:
				if status == .Slow_Down {pending_auth.interval += 5}
				if !post_network_result(
					{kind = .Login_Waiting, login_interval = pending_auth.interval},
				) {return}
			case .Expired, .Failed:
				free_device_auth(&pending_auth)
				pending_auth_active = false
				if !post_network_result({kind = .Login_Error, login_message = message}) {return}
			}
		case .Resolve:
			stream, error := yt.resolve(
				&network_client,
				request.text,
				visitor_data,
				network_stopping,
			)
			if !post_network_result(
				{
					kind = .Stream,
					page = request.page,
					playback = request.playback,
					error = error,
					stream = stream,
				},
			) {return}
			if error == .None && !chan.is_closed(network_requests) {
				segments := sb.fetch(&network_client, request.text)
				if !post_network_result(
					{
						kind = .Segments,
						page = request.page,
						playback = request.playback,
						segments = segments,
					},
				) {return}
			}
		}
	}
}
start_network :: proc() -> bool {
	success := false
	defer if !success {stop_network()}
	error: http.Error
	network_client, error = http.open()
	if error != nil {return false}
	network_event = sdl.EventType(sdl.RegisterEvents(1))
	if u32(network_event) == 0 {return false}
	requests, req_error := chan.create(chan.Chan(Network_Request), 8, context.allocator)
	if req_error != .None {return false}
	network_requests = requests
	results, res_error := chan.create(chan.Chan(Network_Result), 8, context.allocator)
	if res_error != .None {return false}
	network_results = results
	network_thread = thread.create(network_main)
	if network_thread == nil {return false}
	thread.start(network_thread)
	if load_auth() {
		signed_in = auth_active >= 0
		if token := current_auth(); token != nil {
			yt.set_access_token(token.access_token)
			_ = submit_network({kind = .Account})
		}
	}
	success = true
	return true
}
stop_network :: proc() {
	_ = chan.close(network_requests)
	_ = chan.close(network_results)
	if network_thread != nil {thread.destroy(network_thread); network_thread = nil}
	for {
		request, ok := chan.try_recv(network_requests)
		if !ok {break}
		delete(request.text)
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
}
submit_network :: proc(request: Network_Request) -> bool {
	if chan.try_send(network_requests, request) {return true}
	// The UI never blocks behind old input. Keep only its latest pending job.
	if previous, ok := chan.try_recv(network_requests); ok {delete(previous.text)}
	if chan.try_send(network_requests, request) {return true}
	delete(request.text)
	return false
}
clear_catalog :: proc() {
	for &texture in textures {
		if texture != nil {sdl.DestroyTexture(texture); texture = nil}
	}
	model.catalog_destroy(&catalog)
}
start_search :: proc(query: string = "Linus Tech Tips") {
	clean_query := strings.trim_space(query)
	if clean_query == "" || len(clean_query) > 512 {return}
	// Clone before clearing the old page; query may point into its text.
	owned := strings.clone(clean_query)
	clear_catalog()
	catalog.query = strings.clone(owned)
	page += 1
	selected = 0
	search_loading = true
	rail_active = .Search
	rail_focus = false
	library_focus_pending = true
	if scroll := clay.GetScrollContainerData(clay.ID("library-scroll"));
	   scroll.found {scroll.scrollPosition^ = {}}
	notice = ""
	dirty = true
	if !submit_network(
		{kind = .Search, page = page, text = owned},
	) {search_loading = false; notice = "network is unavailable"}
}
resolve_selected :: proc() {
	if selected < 0 || selected >= len(catalog.videos) {return}
	playback += 1
	yt.remove_local_hls()
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
			text = strings.clone(catalog.videos[selected].id),
		},
	) {
		resolving = false; browsing = true; notice = "network is unavailable"
	}
}
poll_network :: proc(renderer: ^sdl.Renderer) {
	// Bound image uploads per frame so input is still serviced during loading.
	for _ in 0 ..< 2 {
		result, ok := chan.try_recv(network_results)
		if !ok {break}
		defer free_network_result(&result)
		#partial switch result.kind {
		case .Account:
			if token := current_auth(); token != nil {
				if result.login_name != "" {
					delete(token.name)
					token.name = strings.clone(result.login_name)
				}
				if result.login_avatar != "" {
					delete(token.avatar_url)
					token.avatar_url = strings.clone(result.login_avatar)
				}
				_ = save_auth()
			}
			set_account_avatar(renderer, result.bytes[:])
			dirty = true
			continue
		case .Avatar:
			set_account_avatar(renderer, result.bytes[:])
			dirty = true
			continue
		case .Login_Code:
			open_login_screen(result.login_code, result.login_url, result.login_interval)
			login_waiting = false
			login_next_poll = sdl.GetTicks() + u64(max(result.login_interval, 1)) * 1000
			dirty = true
			continue
		case .Login_Waiting:
			login_waiting = false
			login_interval_ms = u64(max(result.login_interval, 1)) * 1000
			login_next_poll = sdl.GetTicks() + login_interval_ms
			dirty = true
			continue
		case .Login_Authorized:
			login_waiting = false
			if len(auth_accounts) < MAX_ACCOUNTS {
				append(&auth_accounts, result.auth_token)
				result.auth_token = {}
				auth_active = len(auth_accounts) - 1
				_ = save_auth()
			}
			if token := current_auth(); token != nil {yt.set_access_token(token.access_token)}
			signed_in = true
			login_add_account = false
			account_menu = false
			set_account_avatar(renderer, result.bytes[:])
			close_login_screen()
			notice = "signed in"
			dirty = true
			continue
		case .Login_Error:
			login_waiting = false
			login_next_poll = 0
			if result.login_message != "" {
				delete(login_message)
				login_message = strings.clone(result.login_message)
			}
			dirty = true
			continue
		case:
		}
		if result.page != page {continue}
		#partial switch result.kind {
		case .Catalog:
			search_loading = false
			if result.error != .None {notice = "search failed; try again"; dirty = true; continue}
			clear_catalog()
			catalog = result.catalog; result.catalog = {}
			notice = len(catalog.videos) == 0 ? "no videos found" : ""
			library_focus_pending = true
		case .Cover:
			if result.index < 0 || result.index >= len(catalog.videos) {continue}
			io := sdl.IOFromConstMem(raw_data(result.bytes), uint(len(result.bytes)))
			if io == nil {continue}
			texture := img.LoadTexture_IO(renderer, io, true)
			if texture == nil {continue}
			_ = sdl.SetTextureBlendMode(texture, sdl.BLENDMODE_BLEND)
			_ = sdl.SetTextureScaleMode(texture, .LINEAR)
			if textures[result.index] != nil {sdl.DestroyTexture(textures[result.index])}
			textures[result.index] = texture
		case .Stream:
			if browsing || return_to_grid || !resolving || result.playback != playback {continue}
			resolving = false
			if result.error != .None {
				browsing = true
				notice =
					result.error == .No_Direct_Stream ? "YouTube did not provide a supported direct stream" : "video resolution failed; try again"
			} else {
				load_video(result.stream.url)
			}
		case .Segments:
			if browsing || return_to_grid || result.playback != playback {continue}
			delete(sponsor_segments)
			sponsor_segments = result.segments
			fmt.println("sponsor segments loaded:", len(sponsor_segments))
			result.segments = nil
		case:
		}
		dirty = true
	}
}
