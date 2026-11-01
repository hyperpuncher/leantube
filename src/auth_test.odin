#+test
package main

import "core:os"
import "core:strings"
import "core:testing"

@(test)
account_save_keeps_previous_file_when_staging_fails :: proc(t: ^testing.T) {
	directory, error := os.make_directory_temp("/tmp", "leantube-auth-", context.allocator)
	if !testing.expect(t, error == nil) {return}
	defer {os.remove_all(directory); delete(directory)}
	saved_accounts, saved_active, saved_directory := auth_accounts, auth_active, auth_directory
	auth_accounts = make([dynamic]Auth_Token)
	append(&auth_accounts, Auth_Token{access_token = "fixture", name = "Alice"})
	auth_active, auth_directory = 0, directory
	defer {
		delete(auth_accounts)
		auth_accounts, auth_active, auth_directory = saved_accounts, saved_active, saved_directory
	}
	path := auth_path()
	defer delete(path)
	if !testing.expect(t, save_auth()) {return}
	previous, read_error := os.read_entire_file(path, context.allocator)
	if !testing.expect(t, read_error == nil) {return}
	defer delete(previous)
	info, stat_error := os.stat(path, context.allocator)
	if !testing.expect(t, stat_error == nil) {return}
	defer os.file_info_delete(info, context.allocator)
	testing.expect_value(t, info.mode, os.Permissions{.Read_User, .Write_User})
	temporary := strings.concatenate({path, ".new"})
	defer delete(temporary)
	if !testing.expect(t, os.make_directory(temporary) == nil) {return}
	blocker := strings.concatenate({temporary, "/block"})
	defer delete(blocker)
	if !testing.expect(t, os.write_entire_file(blocker, "fixture") == nil) {return}
	auth_accounts[0].name = "Bob"
	testing.expect(t, !save_auth())
	retained, retained_error := os.read_entire_file(path, context.allocator)
	if !testing.expect(t, retained_error == nil) {return}
	defer delete(retained)
	testing.expect_value(t, string(retained), string(previous))
	os.remove_all(temporary)
	testing.expect(t, save_auth())
	replaced, replaced_error := os.read_entire_file(path, context.allocator)
	if !testing.expect(t, replaced_error == nil) {return}
	defer delete(replaced)
	testing.expect(t, strings.contains(string(replaced), "Bob"))
}
