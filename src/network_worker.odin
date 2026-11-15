#+build !wasi
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

// The UI and the web demo share the request and result channels. These
// services exist only in native builds.
network_thread: ^thread.Thread
network_client: http.Client
pending_auth: Device_Auth
pending_auth_active: bool

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
network_main :: proc(_: ^thread.Thread) {
	session_auth: Auth_Token
	defer {free_auth_token(&session_auth); yt.set_access_token("")}
	session_account: u32
	refresh_at: u64
	visitor_data: string
	defer delete(visitor_data)
	history: yt.Watch_History
	defer yt.watch_history_destroy(&history)
	history_playback: u32
	history_timestamp: i64
	for {
		request, ready := chan.recv(network_requests)
		if !ready {return}
		defer free_network_request(&request)
		// On shutdown, finish queued history reports without loading more pages or images.
		if network_stopping() && request.kind != .Watch_History {continue}
		switch request.kind {
		case .Account_Avatar:
			avatar := load_cached_image(image_loader.cache, &network_client, request.text, 128)
			source := request.text
			request.text = ""
			if !post_network_result(
				{kind = .Account_Avatar, image_source = source, surface = avatar},
			) {return}
		case .Use_Account:
			yt.watch_history_destroy(&history)
			history_playback = 0
			free_auth_token(&session_auth)
			session_auth = request.auth_token
			request.auth_token = {}
			session_account = request.account
			delete(visitor_data); visitor_data = ""
			set_image_visitor("")
			if session_auth.access_token == "" {yt.set_access_token(""); continue}
			refreshed := refresh_auth(&network_client, &session_auth)
			refresh_at =
				sdl.GetTicks() + u64(refreshed ? max(session_auth.expires_in - 60, 30) : 30) * 1000
			yt.set_access_token(session_auth.access_token)
			name, avatar_url := yt.account_info(&network_client)
			if name != "" {delete(session_auth.name); session_auth.name = name} else {delete(name)}
			if avatar_url !=
			   "" {delete(session_auth.avatar_url); session_auth.avatar_url = avatar_url} else {delete(avatar_url)}
			avatar := load_cached_image(
				image_loader.cache,
				&network_client,
				session_auth.avatar_url,
				128,
			)
			if !post_network_result(
				{
					kind = .Account,
					account = session_account,
					auth_token = clone_auth_token(session_auth),
					surface = avatar,
				},
			) {return}
		case .Search, .Browse, .Card_Action, .Card_Membership, .Watch_History:
			if request.kind == .Watch_History &&
			   (request.account != session_account || session_auth.access_token == "") {continue}
			if session_auth.access_token != "" && sdl.GetTicks() >= refresh_at {
				refreshed := refresh_auth(&network_client, &session_auth)
				if refreshed {
					yt.set_access_token(session_auth.access_token)
					if !network_stopping() &&
					   !post_network_result(
							   {
								   kind = .Account,
								   account = session_account,
								   auth_token = clone_auth_token(session_auth),
							   },
						   ) {return}
				}
				refresh_at =
					sdl.GetTicks() +
					u64(refreshed ? max(session_auth.expires_in - 60, 30) : 30) * 1000
			}
			if request.kind == .Watch_History {
				error: yt.Error
				if history_playback != request.playback {
					yt.watch_history_destroy(&history)
					if history_timestamp == 0 {
						history_timestamp = yt.fetch_signature_timestamp(&network_client)
					}
					history, error = yt.fetch_watch_history(
						&network_client,
						request.text,
						visitor_data,
						history_timestamp,
					)
					if error == .None {
						history_playback = request.playback
					} else {
						history_timestamp = 0
					}
				}
				if error == .None {
					error = yt.report_watch_history(
						&network_client,
						&history,
						request.history_start,
						request.position_ms / 1000,
						request.finished,
					)
				}
				if error != .None {fmt.eprintf("watch history update failed: %v\n", error)}
				continue
			}
			if request.kind == .Card_Action || request.kind == .Card_Membership {
				result := Network_Result {
					kind  = .Card_Action,
					page  = request.page,
					index = request.index,
				}
				if request.kind == .Card_Membership {
					result.kind = .Card_Membership
					result.actions, result.error = yt.playlist_options(
						&network_client,
						request.text,
					)
				} else {
					result.actions, result.error = yt.perform_card_action(
						&network_client,
						request.action,
					)
					result.append =
						request.action.kind == .Playlists || request.action.kind == .Menu
				}
				if !post_network_result(result) {return}
				continue
			}
			catalog: model.Catalog
			error: yt.Error
			visitor: string
			if request.kind == .Browse {
				catalog, error, visitor = yt.browse(
					&network_client,
					request.text,
					request.continuation,
					request.params,
					request.filter,
					visitor_data,
				)
			} else {
				catalog, error, visitor = yt.search(
					&network_client,
					request.text,
					request.continuation,
					visitor_data,
				)
			}
			delete(visitor_data)
			visitor_data = visitor
			set_image_visitor(visitor_data)
			for &video, i in catalog.videos {video.cover_index = i}
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
			// Bootstrap the same visitor context as normal browsing, without UI navigation.
			if visitor_data == "" {
				lookup, _, visitor := yt.search(&network_client, request.text)
				model.catalog_destroy(&lookup)
				visitor_data = visitor
				set_image_visitor(visitor_data)
			}
			stream, error := yt.resolve(
				&network_client,
				request.text,
				visitor_data,
				network_stopping,
				limits = playback_limits[:],
			)
			// Deliver the skip plan with the sources, before any media read-ahead.
			segments: [dynamic]sb.Segment
			if error == .None &&
			   !network_stopping() {segments = sb.fetch(&network_client, request.text)}
			if !post_network_result(
				{
					kind = .Stream,
					page = request.page,
					playback = request.playback,
					position_ms = request.position_ms,
					start_paused = request.start_paused,
					error = error,
					stream = stream,
					segments = segments,
				},
			) {return}
		}
	}
}
