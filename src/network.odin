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
		Browse,
		Resolve,
		Use_Account,
		Login_Start,
		Login_Poll,
	},
	page, playback: u32,
	text:           string,
	continuation:   string,
	index:          int,
	account:        u32,
	auth_token:     Auth_Token,
}
Network_Result :: struct {
	kind:           enum {
		Catalog,
		Cover,
		Stream,
		Segments,
		Account,
		Login_Code,
		Login_Waiting,
		Login_Authorized,
		Login_Error,
	},
	page, playback: u32,
	index:          int,
	append:         bool,
	error:          yt.Error,
	catalog:        model.Catalog,
	bytes:          [dynamic]u8,
	stream:         yt.Stream,
	segments:       [dynamic]sb.Segment,
	login_code:     string,
	login_url:      string,
	login_message:  string,
	login_interval: int,
	auth_token:     Auth_Token,
	account:        u32,
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
account_revision: u32

free_network_request :: proc(request: ^Network_Request) {
	delete(request.text)
	delete(request.continuation)
	free_auth_token(&request.auth_token)
	request^ = {}
}

free_network_result :: proc(result: ^Network_Result) {
	model.catalog_destroy(&result.catalog)
	delete(result.bytes)
	delete(result.stream.url)
	delete(result.stream.audio_url)
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

network_main :: proc(_: ^thread.Thread) {
	covers: [dynamic]struct {
		source: string,
		index:  int,
	}
	defer {for cover in covers {delete(cover.source)}; delete(covers)}
	next: int
	cover_page: u32
	session_auth: Auth_Token
	defer {free_auth_token(&session_auth); yt.set_access_token("")}
	session_account: u32
	refresh_at: u64
	visitor_data: string
	defer delete(visitor_data)
	for !chan.is_closed(network_requests) {
		request, ready := chan.try_recv(network_requests)
		if !ready && next < len(covers) {
			index := next
			next += 1
			bytes: [dynamic]u8
			if strings.has_prefix(covers[index].source, "https://") {
				response, error := yt.fetch_thumbnail(&network_client, covers[index].source)
				if error == nil &&
				   response.status == 200 {bytes = response.body} else {delete(response.body)}
			} else {
				bytes = yt.thumbnail(&network_client, covers[index].source, network_stopping)
			}
			if len(bytes) > 0 {
				if !post_network_result(
					{kind = .Cover, page = cover_page, index = covers[index].index, bytes = bytes},
				) {return}
			}
			continue
		}
		if !ready {request, ready = chan.recv(network_requests)}
		if !ready {return}
		defer free_network_request(&request)
		switch request.kind {
		case .Use_Account:
			free_auth_token(&session_auth)
			session_auth = request.auth_token
			request.auth_token = {}
			session_account = request.account
			delete(visitor_data); visitor_data = ""
			if session_auth.access_token == "" {yt.set_access_token(""); continue}
			_ = refresh_auth(&network_client, &session_auth)
			refresh_at = sdl.GetTicks() + u64(max(session_auth.expires_in - 60, 0)) * 1000
			yt.set_access_token(session_auth.access_token)
			name, avatar_url := yt.account_info(&network_client)
			if name != "" {delete(session_auth.name); session_auth.name = name} else {delete(name)}
			if avatar_url !=
			   "" {delete(session_auth.avatar_url); session_auth.avatar_url = avatar_url} else {delete(avatar_url)}
			avatar: [dynamic]u8
			if session_auth.avatar_url != "" {
				response, error := yt.fetch_thumbnail(&network_client, session_auth.avatar_url)
				if error == nil &&
				   response.status == 200 {avatar = response.body} else {delete(response.body)}
			}
			if !post_network_result(
				{
					kind = .Account,
					account = session_account,
					auth_token = clone_auth_token(session_auth),
					bytes = avatar,
				},
			) {return}
		case .Search, .Browse:
			if session_auth.access_token != "" && sdl.GetTicks() >= refresh_at {
				if refresh_auth(&network_client, &session_auth) {
					yt.set_access_token(session_auth.access_token)
					if !post_network_result(
						{
							kind = .Account,
							account = session_account,
							auth_token = clone_auth_token(session_auth),
						},
					) {return}
				}
				refresh_at = sdl.GetTicks() + u64(max(session_auth.expires_in - 60, 30)) * 1000
			}
			catalog: model.Catalog
			error: yt.Error
			visitor: string
			if request.kind == .Browse {
				catalog, error, visitor = yt.browse(
					&network_client,
					request.text,
					request.continuation,
				)
			} else {
				catalog, error, visitor = yt.search(&network_client, request.text)
			}
			delete(visitor_data)
			visitor_data = visitor
			if request.continuation == "" {
				cover_page = request.page
				next = 0
				for cover in covers {delete(cover.source)}
				clear(&covers)
			}
			for video, i in catalog.videos {
				append(
					&covers,
					{
						source = strings.clone(
							video.thumbnail_url != "" ? video.thumbnail_url : video.id,
						),
						index = request.index + i,
					},
				)
			}
			if !post_network_result(
				{
					kind = .Catalog,
					page = request.page,
					error = error,
					catalog = catalog,
					append = request.continuation != "",
				},
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
				// Account selection owns profile and avatar loading in one place.
				if !post_network_result({kind = .Login_Authorized, auth_token = token}) {return}
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
	if load_auth() {use_current_account()}
	thread.start(network_thread)
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
}
submit_network :: proc(request: Network_Request) -> bool {
	if chan.try_send(network_requests, request) {return true}
	// Replace old page requests, never pending account or login commands.
	if previous, ok := chan.try_recv(network_requests); ok {
		if previous.kind != .Search && previous.kind != .Browse {
			if !chan.try_send(network_requests, previous) {free_network_request(&previous)}
			request := request
			free_network_request(&request)
			return false
		}
		free_network_request(&previous)
	}
	if chan.try_send(network_requests, request) {return true}
	request := request
	free_network_request(&request)
	return false
}
clear_catalog :: proc() {
	for &texture in textures {
		if texture != nil {sdl.DestroyTexture(texture); texture = nil}
	}
	delete(textures); textures = nil
	model.catalog_destroy(&catalog)
}
start_browse :: proc(id: string) {
	owned := strings.clone(id)
	delete(browse_id)
	browse_id = owned
	clear_catalog()
	page += 1
	selected = 0
	rail_focus = false
	search_loading = true
	library_focus_pending = true
	if scroll := clay.GetScrollContainerData(clay.ID("library-scroll")); scroll.found {
		scroll.scrollPosition^ = {}
	}
	notice = ""
	dirty = true
	if !submit_network({kind = .Browse, page = page, text = strings.clone(browse_id)}) {
		search_loading = false
		notice = "network is unavailable"
	}
}

load_more :: proc() {
	if search_loading || catalog.continuation == "" || browse_id == "" {return}
	search_loading = true
	dirty = true
	if !submit_network(
		{
			kind = .Browse,
			page = page,
			text = strings.clone(browse_id),
			continuation = strings.clone(catalog.continuation),
			index = len(catalog.videos),
		},
	) {
		search_loading = false
		notice = "network is unavailable"
	}
}

open_selected :: proc() {
	if selected < 0 || selected >= len(catalog.videos) {return}
	card := catalog.videos[selected]
	if card.browse_id != "" {
		start_browse(card.browse_id)
	} else {start_video()}
}

start_search :: proc(query: string = "Linus Tech Tips") {
	clean_query := strings.trim_space(query)
	if clean_query == "" || len(clean_query) > 512 {return}
	// Clone before clearing the old page; query may point into its text.
	owned := strings.clone(clean_query)
	delete(browse_id); browse_id = ""
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
			if result.account != account_revision {continue}
			if token := current_auth(); token != nil {
				free_auth_token(token)
				token^ = result.auth_token
				result.auth_token = {}
				_ = save_auth()
			}
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
			use_current_account()
			login_add_account = false
			close_login_screen()
			rail_active = .Subscriptions
			reload_feed()
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
			if result.error !=
			   .None {notice = "could not load this page; try again"; dirty = true; continue}
			if result.append {
				append(&catalog.videos, ..result.catalog.videos[:])
				clear(&result.catalog.videos)
				delete(catalog.continuation)
				catalog.continuation = result.catalog.continuation
				result.catalog.continuation = ""
			} else {
				clear_catalog()
				catalog = result.catalog; result.catalog = {}
			}
			resize(&textures, len(catalog.videos))
			notice = len(catalog.videos) == 0 ? "no items found" : ""
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
