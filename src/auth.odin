package main

import "./http"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

// YouTube TV OAuth client. The device flow needs no browser on the TV.
AUTH_CLIENT_ID :: "861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com"
AUTH_CLIENT_SECRET :: "SboVhoG9s0rNafixCSGGKXAT"
AUTH_SCOPE_FORM :: "https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fyoutube"

Device_Auth :: struct {
	device_code:      string `json:"device_code"`,
	user_code:        string `json:"user_code"`,
	verification_url: string `json:"verification_url"`,
	expires_in:       int `json:"expires_in"`,
	interval:         int `json:"interval"`,
}

Auth_Token :: struct {
	access_token:  string `json:"access_token"`,
	refresh_token: string `json:"refresh_token"`,
	scope:         string `json:"scope"`,
	expires_in:    int `json:"expires_in"`,
	name:          string `json:"name,omitempty"`,
	avatar_url:    string `json:"avatar_url,omitempty"`,
}

Auth_Poll :: enum {
	Pending,
	Slow_Down,
	Authorized,
	Failed,
	Expired,
}

MAX_ACCOUNTS :: 5

auth_accounts: [dynamic]Auth_Token
auth_active := -1

Auth_Store :: struct {
	active:   int,
	accounts: []Auth_Token,
}

current_auth :: proc() -> ^Auth_Token {
	if auth_active < 0 || auth_active >= len(auth_accounts) {return nil}
	return &auth_accounts[auth_active]
}

auth_path :: proc() -> string {
	return fmt.aprintf("%s/.auth.json", app_directory)
}

save_auth :: proc() -> bool {
	path := auth_path()
	defer delete(path)
	if len(auth_accounts) == 0 {
		_ = os.remove(path)
		return true
	}
	store := Auth_Store {
		active   = auth_active,
		accounts = auth_accounts[:],
	}
	data, error := json.marshal(store)
	if error != nil {return false}
	defer delete(data)
	_ = os.remove(path)
	file, open_error := os.open(
		path,
		{.Create, .Write, .Trunc},
		os.Permissions{.Read_User, .Write_User},
	)
	if open_error != nil {return false}
	defer os.close(file)
	written, write_error := os.write(file, data)
	return write_error == nil && written == len(data)
}

free_auth_token :: proc(token: ^Auth_Token) {
	delete(token.access_token)
	delete(token.refresh_token)
	delete(token.scope)
	delete(token.name)
	delete(token.avatar_url)
	token^ = {}
}

load_auth :: proc() -> bool {
	path := auth_path()
	defer delete(path)
	data, read_error := os.read_entire_file_from_path(path, context.allocator)
	if read_error != nil {return false}
	defer delete(data)
	store: Auth_Store
	if json.unmarshal(data, &store) == nil && len(store.accounts) > 0 {
		auth_accounts = make([dynamic]Auth_Token, 0, MAX_ACCOUNTS)
		for token in store.accounts {append(&auth_accounts, token)}
		delete(store.accounts)
		auth_active = clamp(store.active, 0, len(auth_accounts) - 1)
		return true
	}
	token: Auth_Token
	if json.unmarshal(data, &token) != nil || token.access_token == "" {return false}
	auth_accounts = make([dynamic]Auth_Token, 0, MAX_ACCOUNTS)
	append(&auth_accounts, token)
	auth_active = 0
	return true
}

clear_auth :: proc() {
	if token := current_auth(); token != nil {free_auth_token(token)}
	if auth_active >= 0 && auth_active < len(auth_accounts) {
		ordered_remove(&auth_accounts, auth_active)
	}
	auth_active = len(auth_accounts) == 0 ? -1 : min(auth_active, len(auth_accounts) - 1)
	_ = save_auth()
}

begin_login :: proc(client: ^http.Client) -> (Device_Auth, bool) {
	body := fmt.aprintf("client_id=%s&scope=%s", AUTH_CLIENT_ID, AUTH_SCOPE_FORM)
	defer delete(body)
	response, request_error := http.request(
		client,
		"https://oauth2.googleapis.com/device/code",
		body,
		[]string{"Content-Type: application/x-www-form-urlencoded"},
		timeout_ms = 3000,
	)
	if request_error != nil {return {}, false}
	defer delete(response.body)
	if response.status != 200 {return {}, false}
	device: Device_Auth
	if json.unmarshal(response.body[:], &device) != nil {return {}, false}
	if device.device_code == "" || device.user_code == "" || device.verification_url == "" {
		return {}, false
	}
	if device.interval <= 0 {device.interval = 5}
	return device, true
}

poll_login :: proc(client: ^http.Client, device: Device_Auth) -> (Auth_Token, Auth_Poll, string) {
	body := fmt.aprintf(
		"client_id=%s&client_secret=%s&device_code=%s&grant_type=urn:ietf:params:oauth:grant-type:device_code",
		AUTH_CLIENT_ID,
		AUTH_CLIENT_SECRET,
		device.device_code,
	)
	defer delete(body)
	response, request_error := http.request(
		client,
		"https://oauth2.googleapis.com/token",
		body,
		[]string{"Content-Type: application/x-www-form-urlencoded"},
		timeout_ms = 3000,
	)
	if request_error != nil {return {}, .Failed, strings.clone("network")}
	defer delete(response.body)
	token: Auth_Token
	if json.unmarshal(response.body[:], &token) == nil && token.access_token != "" {
		return token, .Authorized, ""
	}
	error: struct {
		error:             string `json:"error"`,
		error_description: string `json:"error_description"`,
	}
	_ = json.unmarshal(response.body[:], &error)
	defer {delete(error.error); delete(error.error_description)}
	switch error.error {
	case "authorization_pending":
		return {}, .Pending, ""
	case "slow_down":
		return {}, .Slow_Down, ""
	case "expired_token":
		return {}, .Expired, strings.clone("code expired")
	case "access_denied":
		return {}, .Failed, strings.clone("access denied")
	}
	if error.error_description != "" {
		return {}, .Failed, strings.clone(error.error_description)
	}
	if response.status != 200 {
		return {}, .Failed, strings.clone("login rejected")
	}
	return {}, .Failed, strings.clone("login failed")
}

free_device_auth :: proc(device: ^Device_Auth) {
	delete(device.device_code)
	delete(device.user_code)
	delete(device.verification_url)
	device^ = {}
}
