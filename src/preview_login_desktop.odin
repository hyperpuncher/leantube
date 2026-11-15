#+build linux:default amd64, linux:default arm64
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

check_account_ui :: proc(renderer: ^sdl.Renderer, surface: ^sdl.Surface) {
	// Local fixtures only. Never load or modify a real account file here.
	saved_accounts, saved_active := auth_accounts, auth_active
	saved_signed_in, saved_avatars := signed_in, account_avatars
	auth_accounts = make([dynamic]Auth_Token)
	append(&auth_accounts, Auth_Token{name = "Alice"}, Auth_Token{name = "Bob"})
	auth_active = 0
	signed_in = true
	account_avatars = {}
	account_avatars[0] = load_texture(renderer, "tests/ui/cover.webp")
	assert(account_avatars[0] != nil)
	defer {
		close_account_avatars()
		delete(auth_accounts)
		auth_accounts, auth_active = saved_accounts, saved_active
		signed_in, account_avatars = saved_signed_in, saved_avatars
		account_menu = false
	}
	snapshot(renderer, surface, "account-avatar")
	avatar := clay.GetElementData(clay.ID("account-avatar"))
	assert(avatar.found && avatar.boundingBox.width == avatar.boundingBox.height)
	assert(!clay.GetElementData(clay.ID("sign-out")).found)
	account_menu = true
	snapshot(renderer, surface, "users")
	assert(clay.GetElementData(clay.ID("account-row", 0)).found)
	assert(clay.GetElementData(clay.ID("account-row", 1)).found)
	assert(clay.GetElementData(clay.ID("add-account")).found)
	assert(clay.GetElementData(clay.ID("sign-out")).found)
	account_menu_selected = 0
	key(sdl.K_DOWN)
	assert(account_menu_selected == 1)
	key(sdl.K_UP)
	assert(account_menu_selected == 0)
	key(sdl.K_AC_BACK)
	assert(!account_menu && running)
}
