#+build !wasi
package main

import "./http"
import "core:encoding/json"
import "core:fmt"
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

Auth_Poll :: enum {
	Pending,
	Slow_Down,
	Authorized,
	Failed,
	Expired,
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
	success := false
	defer if !success {free_device_auth(&device)}
	if json.unmarshal(response.body[:], &device) != nil {return {}, false}
	if device.device_code == "" || device.user_code == "" || device.verification_url == "" {
		return {}, false
	}
	if device.interval <= 0 {device.interval = 5}
	success = true
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
	authorized := json.unmarshal(response.body[:], &token) == nil && token.access_token != ""
	defer if !authorized {free_auth_token(&token)}
	if authorized {
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

refresh_auth :: proc(client: ^http.Client, token: ^Auth_Token) -> bool {
	if token.refresh_token == "" {return false}
	request := struct {
		client_id, client_secret, refresh_token, grant_type: string,
	}{AUTH_CLIENT_ID, AUTH_CLIENT_SECRET, token.refresh_token, "refresh_token"}
	body, error := json.marshal(request)
	if error != nil {return false}
	defer delete(body)
	response, request_error := http.request(
		client,
		"https://oauth2.googleapis.com/token",
		string(body),
		{"Content-Type: application/json"},
		timeout_ms = 5000,
	)
	if request_error != nil {return false}
	defer delete(response.body)
	if response.status != 200 {return false}
	refreshed: Auth_Token
	defer free_auth_token(&refreshed)
	if json.unmarshal(response.body[:], &refreshed) != nil ||
	   refreshed.access_token == "" {return false}
	delete(token.access_token)
	token.access_token = refreshed.access_token
	refreshed.access_token = ""
	token.expires_in = refreshed.expires_in
	return true
}

free_device_auth :: proc(device: ^Device_Auth) {
	delete(device.device_code)
	delete(device.user_code)
	delete(device.verification_url)
	device^ = {}
}
