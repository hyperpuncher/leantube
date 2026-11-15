package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

Auth_Token :: struct {
	access_token:  string `json:"access_token"`,
	refresh_token: string `json:"refresh_token"`,
	scope:         string `json:"scope"`,
	expires_in:    int `json:"expires_in"`,
	name:          string `json:"name,omitempty"`,
	avatar_url:    string `json:"avatar_url,omitempty"`,
}

MAX_ACCOUNTS :: 5

auth_accounts: [dynamic]Auth_Token
auth_active := -1
auth_directory: string

Auth_Store :: struct {
	active:   int,
	accounts: []Auth_Token,
}

current_auth :: proc() -> ^Auth_Token {
	if auth_active < 0 || auth_active >= len(auth_accounts) {return nil}
	return &auth_accounts[auth_active]
}

auth_path :: proc() -> string {
	directory := auth_directory
	if directory == "" {directory = app_directory}
	return fmt.aprintf("%s/.auth.json", directory)
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
	// Replace only after the private staging file has been written and closed.
	temporary := strings.concatenate({path, ".new"})
	defer delete(temporary)
	_ = os.remove(temporary)
	defer os.remove(temporary)
	file, open_error := os.open(
		temporary,
		{.Create, .Write, .Excl},
		os.Permissions{.Read_User, .Write_User},
	)
	if open_error != nil {return false}
	written, write_error := os.write(file, data)
	close_error := os.close(file)
	if write_error != nil || written != len(data) || close_error != nil {return false}
	return os.rename(temporary, path) == nil
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
	defer {for &token in store.accounts {free_auth_token(&token)}; delete(store.accounts)}
	if json.unmarshal(data, &store) == nil && len(store.accounts) > 0 {
		if len(store.accounts) > MAX_ACCOUNTS {return false}
		auth_accounts = make([dynamic]Auth_Token, 0, MAX_ACCOUNTS)
		for &token in store.accounts {append(&auth_accounts, token); token = {}}
		auth_active = clamp(store.active, 0, len(auth_accounts) - 1)
		return true
	}
	token: Auth_Token
	defer free_auth_token(&token)
	if json.unmarshal(data, &token) != nil || token.access_token == "" {return false}
	auth_accounts = make([dynamic]Auth_Token, 0, MAX_ACCOUNTS)
	append(&auth_accounts, token)
	token = {}
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

clone_auth_token :: proc(token: Auth_Token) -> Auth_Token {
	copy := token
	copy.access_token = strings.clone(token.access_token)
	copy.refresh_token = strings.clone(token.refresh_token)
	copy.scope = strings.clone(token.scope)
	copy.name = strings.clone(token.name)
	copy.avatar_url = strings.clone(token.avatar_url)
	return copy
}
