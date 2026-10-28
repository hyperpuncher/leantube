package main

import clay "../vendor/clay"
import "core:strings"
import "core:sync/chan"
import sdl "vendor:sdl3"

check_login_ui :: proc(renderer: ^sdl.Renderer, surface: ^sdl.Surface) {
	// Device codes and replies are fixtures. No real account or request is used.
	saved_signed_in := signed_in
	saved_search := search_editing
	defer {
		close_login_screen()
		stop_network()
		signed_in = saved_signed_in
		search_editing = saved_search
	}
	network_requests, _ = chan.create(chan.Chan(Network_Request), 2, context.allocator)
	network_results, _ = chan.create(chan.Chan(Network_Result), 2, context.allocator)
	signed_in = false
	search_editing = false
	activate_navigation(.Home)
	assert(login_screen && login_waiting)
	request, ready := chan.try_recv(network_requests)
	assert(ready && request.kind == .Login_Start)
	snapshot(renderer, surface, "login-loading")
	chan.send(
		network_results,
		Network_Result {
			kind = .Login_Code,
			login_code = strings.clone("TEST-CODE"),
			login_url = strings.clone("https://www.google.com/device"),
			login_interval = 5,
		},
	)
	poll_network(renderer)
	snapshot(renderer, surface, "login")
	assert(login_qr != nil, "the local preview must generate a real QR code")
	content := clay.GetElementData(clay.ID("login-content"))
	code := clay.GetElementData(clay.ID("login-code"))
	qr := clay.GetElementData(clay.ID("login-qr"))
	action := clay.GetElementData(clay.ID("login-search"))
	assert(content.found && code.found && qr.found && action.found)
	assert(qr.boundingBox.width > 0 && qr.boundingBox.width == qr.boundingBox.height)
	assert(content.boundingBox.x >= 0 && content.boundingBox.y >= 0)
	assert(content.boundingBox.x + content.boundingBox.width <= view_width)
	assert(content.boundingBox.y + content.boundingBox.height <= view_height)
	assert(!clay.GetElementData(clay.ID("login-card")).found)
	login_next_poll = 1
	poll_login_tick()
	request, ready = chan.try_recv(network_requests)
	assert(ready && request.kind == .Login_Poll)
	chan.send(
		network_results,
		Network_Result {
			kind = .Login_Error,
			login_message = strings.clone("This code has expired. Get a new code to sign in."),
		},
	)
	poll_network(renderer)
	snapshot(renderer, surface, "login-error")
	assert(login_failed())
	assert(clay.GetElementData(clay.ID("login-retry")).found)
	status := clay.GetElementData(clay.ID("login-status"))
	assert(status.found && status.boundingBox.height > 0)
	assert(status.boundingBox.y + status.boundingBox.height <= view_height)
	assert(login_code == "" && login_qr == nil, "failed login must hide the expired code")
	key(sdl.K_DOWN)
	key(sdl.K_RETURN)
	request, ready = chan.try_recv(network_requests)
	assert(ready && request.kind == .Login_Start && login_code == "")
	key(sdl.K_ESCAPE)
	assert(!login_screen && search_editing)
	// A canceled request must not open the sign-in screen again.
	chan.send(
		network_results,
		Network_Result {
			kind = .Login_Code,
			login_code = strings.clone("OLD-CODE"),
			login_url = strings.clone("https://www.google.com/device"),
		},
	)
	poll_network(renderer)
	assert(!login_screen && login_code == "")
}
