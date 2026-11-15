package main

import "./model"
import sb "./sponsorblock"
import yt "./youtube"
import "core:fmt"
import "core:math"
import "core:sort"
import "core:strings"
import "core:sync/chan"
import "core:thread"
import sdl "vendor:sdl3"
import img "vendor:sdl3/image"

// Decode and prefilter on the worker. The result owns its pixels, not bytes.
decode_image :: proc(bytes: []u8, target: i32 = 0) -> ^sdl.Surface {
	if len(bytes) == 0 {return nil}
	io := sdl.IOFromConstMem(raw_data(bytes), uint(len(bytes)))
	if io == nil {return nil}
	surface := img.Load_IO(io, true)
	for target > 0 && surface != nil && max(surface.w, surface.h) > target {
		ratio := max(f32(0.5), f32(target) / f32(max(surface.w, surface.h)))
		width := max(1, i32(math.round(f32(surface.w) * ratio)))
		height := max(1, i32(math.round(f32(surface.h) * ratio)))
		next := sdl.ScaleSurface(surface, width, height, .LINEAR)
		sdl.DestroySurface(surface)
		surface = next
	}
	return surface
}

network_main :: proc(_: ^thread.Thread) {
	directory := auth_directory != "" ? auth_directory : app_directory
	cache_directory := fmt.aprintf("%s/.cache/images", directory)
	defer delete(cache_directory)
	cache := Image_Cache {
		directory     = cache_directory,
		maximum_bytes = IMAGE_CACHE_BYTES,
	}
	cache_path := strings.clone_to_cstring(cache.directory)
	defer delete(cache_path)
	if !sdl.CreateDirectory(cache_path) || !trim_image_cache(cache) {
		fmt.eprintln("image cache is unavailable")
	}
	covers: [dynamic]Image_Request
	defer {for cover in covers {delete(cover.source)}; delete(covers)}
	avatars := make(map[string]string)
	defer {for id, url in avatars {delete(id); delete(url)}; delete(avatars)}
	next: int
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
		request, ready := chan.try_recv(network_requests)
		if !ready && next < len(covers) && !network_stopping() {
			index := next
			next += 1
			source := covers[index].source
			cache_source := source
			surface: ^sdl.Surface
			if covers[index].target > 0 && strings.has_prefix(source, "UC") {
				if url, found := avatars[source]; found {
					source = url
				} else if surface = read_cached_image(cache, source, covers[index].target);
				   surface == nil {
					resolved := yt.channel_avatar(&network_client, source, visitor_data)
					if resolved != "" {avatars[strings.clone(source)] = resolved; next -= 1}
					// Check for a new section before downloading the resolved image.
					continue
				}
			}
			if surface == nil {
				surface = load_cached_image(
					cache,
					&network_client,
					source,
					covers[index].target,
					cache_source = cache_source,
				)
			}
			if surface != nil {
				if !post_network_result(
					   {
						   kind = covers[index].target > 0 ? .Channel_Avatar : .Cover,
						   page = covers[index].page,
						   index = covers[index].index,
						   playback = covers[index].playback,
						   surface = surface,
					   },
				   ) &&
				   !network_stopping() {return}
			}
			continue
		}
		if !ready {request, ready = chan.recv(network_requests)}
		if !ready {return}
		defer free_network_request(&request)
		// On shutdown, finish queued history reports without loading more pages or images.
		if network_stopping() && request.kind != .Watch_History {continue}
		switch request.kind {
		case .Images:
			append(&covers, ..request.images[:])
			clear(&request.images)
			// Serve disk hits in card order before any downloads or URL lookups.
			for &image in covers[next:] {image.cached = cached_image_exists(cache, image.source)}
			sort.merge_sort_proc(covers[next:], proc(a, b: Image_Request) -> int {
				if a.cached != b.cached {return int(b.cached) - int(a.cached)}
				if a.cached {return 0}
				return int(a.target > 0) - int(b.target > 0)
			})
		case .Account_Avatar:
			avatar := load_cached_image(cache, &network_client, request.text, 128)
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
			if session_auth.access_token == "" {yt.set_access_token(""); continue}
			refreshed := refresh_auth(&network_client, &session_auth)
			refresh_at =
				sdl.GetTicks() + u64(refreshed ? max(session_auth.expires_in - 60, 30) : 30) * 1000
			yt.set_access_token(session_auth.access_token)
			name, avatar_url := yt.account_info(&network_client)
			if name != "" {delete(session_auth.name); session_auth.name = name} else {delete(name)}
			if avatar_url !=
			   "" {delete(session_auth.avatar_url); session_auth.avatar_url = avatar_url} else {delete(avatar_url)}
			avatar := load_cached_image(cache, &network_client, session_auth.avatar_url, 128)
			if !post_network_result(
				{
					kind = .Account,
					account = session_account,
					auth_token = clone_auth_token(session_auth),
					surface = avatar,
				},
			) {return}
		case .Search, .Browse, .Card_Action, .Card_Membership, .Player_Channel, .Watch_History:
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
			if request.kind == .Player_Channel {
				append(
					&covers,
					{
						source = strings.clone(request.text),
						index = -1,
						target = 2 * PLAYER_AVATAR_SIZE,
						page = request.page,
						playback = request.playback,
					},
				)
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
			if request.continuation == "" {
				next = 0
				for cover in covers {delete(cover.source)}
				clear(&covers)
			}
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
