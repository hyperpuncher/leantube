package main

import clay "../vendor/clay"
import "./http"
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
		Player_Channel,
		Images,
		Use_Account,
		Account_Avatar,
		Login_Start,
		Login_Poll,
		Card_Action,
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
	images:         [dynamic]Image_Request,
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

// Playing controls fade out after a few quiet seconds and any input revives them.
// A zero deadline means hidden.
PLAYER_CONTROLS_MS :: 3000
controls_until: u64

show_player_controls :: proc() {controls_until = sdl.GetTicks() + PLAYER_CONTROLS_MS}

player_controls_visible :: proc() -> bool {
	return(
		paused ||
		!loaded ||
		sdl.GetTicks() < controls_until ||
		clay.PointerOver(clay.ID("controls")) ||
		clay.PointerOver(clay.ID("player-header")) \
	)
}

expire_player_controls :: proc() {
	if browsing || controls_until == 0 || player_controls_visible() {return}
	controls_until = 0
	dirty = true
}
sponsor_segments: [dynamic]sb.Segment
pending_auth: Device_Auth
pending_auth_active: bool
account_revision: u32

free_network_request :: proc(request: ^Network_Request) {
	delete(request.text)
	delete(request.continuation)
	delete(request.params); delete(request.filter)
	delete(request.action.label); delete(request.action.target); delete(request.action.payload)
	free_auth_token(&request.auth_token)
	for image in request.images {delete(image.source)}
	delete(request.images)
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
			_ = refresh_auth(&network_client, &session_auth)
			refresh_at = sdl.GetTicks() + u64(max(session_auth.expires_in - 60, 0)) * 1000
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
		case .Search, .Browse, .Card_Action, .Player_Channel, .Watch_History:
			if request.kind == .Watch_History &&
			   (request.account != session_account || session_auth.access_token == "") {continue}
			if session_auth.access_token != "" && sdl.GetTicks() >= refresh_at {
				if refresh_auth(&network_client, &session_auth) {
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
				refresh_at = sdl.GetTicks() + u64(max(session_auth.expires_in - 60, 30)) * 1000
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
			if request.kind == .Card_Action {
				actions, error := yt.perform_card_action(&network_client, request.action)
				if !post_network_result(
					{
						kind = .Card_Action,
						page = request.page,
						index = request.index,
						actions = actions,
						error = error,
						append = request.action.kind == .Playlists || request.action.kind == .Menu,
					},
				) {return}
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
				catalog, error, visitor = yt.search(&network_client, request.text)
			}
			delete(visitor_data)
			visitor_data = visitor
			if request.continuation == "" {
				next = 0
				for cover in covers {delete(cover.source)}
				clear(&covers)
			}
			for &video, i in catalog.videos {video.cover_index = request.index + i}
			if request.kind == .Browse && request.text == "FEsubscriptions" {
				model.sort_latest(catalog.videos[:])
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
	// Replace old page requests, never pending account or login commands.
	if previous, ok := chan.try_recv(network_requests); ok {
		if previous.kind != .Search && previous.kind != .Browse && previous.kind != .Images {
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

// Background reports must not discard foreground navigation or account commands.
queue_watch_history :: proc(
	id: string,
	start, position: f64,
	account, generation: u32,
	finished: bool,
) -> bool {
	request := Network_Request {
		kind          = .Watch_History,
		text          = strings.clone(id),
		account       = account,
		playback      = generation,
		history_start = start,
		position_ms   = position * 1000,
		finished      = finished,
	}
	if chan.try_send(network_requests, request) {return true}
	free_network_request(&request)
	return false
}

clear_catalog :: proc(keep_channel: bool = false) {
	labels_release()
	clear_player_channel()
	close_card_menu()
	catalog_revision += 1
	for &texture in textures {
		if texture != nil {sdl.DestroyTexture(texture); texture = nil}
	}
	delete(textures); textures = nil
	for texture in card_avatars {if texture != nil {sdl.DestroyTexture(texture)}}
	delete(card_avatars); card_avatars = nil
	channel: model.Channel
	if keep_channel {channel = catalog.channel; catalog.channel = {}}
	model.catalog_destroy(&catalog)
	catalog.channel = channel
	if !keep_channel &&
	   channel_avatar != nil {sdl.DestroyTexture(channel_avatar); channel_avatar = nil}
}
start_browse :: proc(id: string, params: string = "", filter: string = "", remember: bool = true) {
	owned, owned_params, owned_filter :=
		strings.clone(id), strings.clone(params), strings.clone(filter)
	if remember && id != browse_id && (browse_id != "" || catalog.query != "") {remember_browse()}
	keep_channel := id == browse_id && catalog.channel.id == id
	delete(browse_id); delete(browse_params); delete(browse_filter)
	browse_id, browse_params, browse_filter = owned, owned_params, owned_filter
	clear_catalog(keep_channel)
	channel_focus = false
	restore_selected = -1
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
	if !submit_network(
		{
			kind = .Browse,
			page = page,
			text = strings.clone(browse_id),
			params = strings.clone(browse_params),
			filter = strings.clone(browse_filter),
		},
	) {
		search_loading = false
		show_notice("Network unavailable")
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
		show_notice("Network unavailable")
	}
}

open_selected :: proc() {
	if selected < 0 || selected >= len(catalog.videos) {return}
	card := catalog.videos[selected]
	if card.browse_id != "" {
		start_browse(card.browse_id)
	} else {start_video()}
}

start_search :: proc(query: string = "Linus Tech Tips", keep_history: bool = false) {
	clean_query := strings.trim_space(query)
	if clean_query == "" || len(clean_query) > 512 {return}
	// Clone before clearing the old page; query may point into its text.
	owned := strings.clone(clean_query)
	if !keep_history {clear_browse_history()}
	delete(browse_id); browse_id = ""
	delete(browse_params); browse_params = ""
	delete(browse_filter); browse_filter = ""
	channel_focus = false
	restore_selected = -1
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
	) {search_loading = false; show_notice("Network unavailable")}
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
// Cover replies use the original feed position, not the sorted grid position.
sort_subscriptions :: proc(preserve_selection: bool) {
	if len(catalog.videos) == 0 {return}
	selected_cover := preserve_selection ? catalog.videos[selected].cover_index : -1
	model.sort_latest(catalog.videos[:])
	for video, i in catalog.videos {
		if video.cover_index == selected_cover {selected = i}
	}
}

poll_network :: proc(renderer: ^sdl.Renderer) {
	// Bound image uploads per frame so input is still serviced during loading.
	for _ in 0 ..< 2 {
		result, ok := chan.try_recv(network_results)
		if !ok {break}
		defer free_network_result(&result)
		#partial switch result.kind {
		case .Account_Avatar:
			set_account_avatar(renderer, result.surface, result.image_source)
			dirty = true
			continue
		case .Account:
			if result.account != account_revision {continue}
			if token := current_auth(); token != nil {
				free_auth_token(token)
				token^ = result.auth_token
				result.auth_token = {}
				_ = save_auth()
				set_account_avatar(renderer, result.surface, token.avatar_url)
			}
			dirty = true
			continue
		case .Login_Code:
			if !login_screen {continue}
			open_login_screen(result.login_code, result.login_url, result.login_interval)
			continue
		case .Login_Waiting:
			if !login_screen {continue}
			login_waiting = false
			login_interval_ms = u64(max(result.login_interval, 1)) * 1000
			login_next_poll = sdl.GetTicks() + login_interval_ms
			dirty = true
			continue
		case .Login_Authorized:
			if !login_screen {continue}
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
			if !login_screen {continue}
			login_waiting = false
			login_next_poll = 0
			delete(login_code); login_code = ""
			if login_qr != nil {sdl.DestroyTexture(login_qr); login_qr = nil}
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
		case .Card_Action:
			if (!card_menu && !card_menu_waiting) || result.index != card_menu_revision {continue}
			card_menu_waiting = false
			if !card_menu {
				cover := watch_later_cover
				close_card_menu()
				if result.error == .None {
					watch_later_cover = cover
					watch_later_saved_until = sdl.GetTicks() + 1000
				} else {show_notice("Could not save to Watch later")}
			} else if result.error != .None {
				card_menu_error = "Action failed"
			} else if result.append {
				model.card_actions_destroy(&card_menu_actions)
				card_menu_actions = result.actions
				result.actions = nil
				card_menu_selected = 0
			} else {
				close_card_menu()
				reload_feed()
			}
		case .Catalog:
			first_cover := result.append ? len(catalog.videos) : 0
			search_loading = false
			if result.error != .None {show_notice("Could not load this page"); continue}
			if result.append {
				append(&catalog.videos, ..result.catalog.videos[:])
				clear(&result.catalog.videos)
				delete(catalog.continuation)
				catalog.continuation = result.catalog.continuation
				result.catalog.continuation = ""
			} else {
				same_channel :=
					result.catalog.channel.id != "" &&
					result.catalog.channel.id == catalog.channel.id
				if same_channel &&
				   channel_avatar != nil &&
				   result.catalog.channel.avatar_url != "" &&
				   result.catalog.channel.avatar_url != catalog.channel.avatar_url {
					sdl.DestroyTexture(channel_avatar)
					channel_avatar = nil
				}
				if same_channel && result.catalog.channel.title == "" {
					sorts := result.catalog.channel.sorts
					result.catalog.channel.sorts = nil
					model.channel_destroy(&result.catalog.channel)
					result.catalog.channel = catalog.channel
					catalog.channel = {}
					if len(sorts) > 0 {
						model.channel_options_destroy(&result.catalog.channel.sorts)
						result.catalog.channel.sorts = sorts
					}
				}
				clear_catalog(same_channel)
				model.channel_destroy(&catalog.channel)
				catalog = result.catalog; result.catalog = {}
				if restore_selected >= 0 {
					selected = clamp(restore_selected, 0, max(0, len(catalog.videos) - 1))
					restore_selected = -1
				}
			}
			resize(&textures, len(catalog.videos))
			resize(&card_avatars, len(catalog.videos))
			if browse_id == "FEsubscriptions" {sort_subscriptions(result.append)}
			queue_catalog_images(first_cover)
			catalog_revision += 1
			notice = ""
			if !result.append {library_focus_pending = true}
		case .Cover, .Channel_Avatar:
			slot := &channel_avatar
			if result.kind == .Channel_Avatar && result.playback != 0 {
				if browsing || result.playback != playback {continue}
				slot = &player_channel_avatar
			}
			if result.kind == .Cover || result.index >= 0 {
				index := result.index
				if index < 0 || index >= len(textures) {continue}
				slot = result.kind == .Cover ? &textures[index] : &card_avatars[index]
			}
			if result.surface == nil {continue}
			texture := sdl.CreateTextureFromSurface(renderer, result.surface)
			if texture == nil {continue}
			_ = sdl.SetTextureBlendMode(texture, sdl.BLENDMODE_BLEND)
			_ = sdl.SetTextureScaleMode(texture, .LINEAR)
			if slot^ != nil {sdl.DestroyTexture(slot^)}
			slot^ = texture
		case .Stream:
			if browsing || return_to_grid || !resolving || result.playback != playback {continue}
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
					_ = submit_network(
						{
							kind = .Player_Channel,
							page = page,
							playback = playback,
							text = strings.clone(player_channel_id),
						},
					)
				}
				show_player_controls()
			}
		case:
		}
		dirty = true
	}
}
