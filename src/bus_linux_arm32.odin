package main

import "base:runtime"
import "core:c"
import "core:encoding/json"
import "core:fmt"
import sdl "vendor:sdl3"

LS_Error :: struct {
	error_code: c.int,
	message:    cstring,
	file:       cstring,
	line:       c.int,
	func:       cstring,
	padding:    rawptr,
	magic:      c.ulong,
}
Callback :: #type proc "c" (_: rawptr, _: rawptr, _: rawptr) -> bool
LS_Register_Legacy :: #type proc "c" (
	name: cstring,
	handle: ^rawptr,
	public_bus: bool,
	error: ^LS_Error,
) -> bool

foreign import luna "system:luna-service2"
foreign luna {
	LSRegister :: proc(name: cstring, handle: ^rawptr, error: ^LS_Error) -> bool ---
	LSGmainContextAttach :: proc(handle, main_context: rawptr, error: ^LS_Error) -> bool ---
	LSUnregister :: proc(handle: rawptr, error: ^LS_Error) -> bool ---
	LSCall :: proc(handle: rawptr, uri, payload: cstring, callback: Callback, data: rawptr, token: ^c.ulong, error: ^LS_Error) -> bool ---
	LSCallOneReply :: proc(handle: rawptr, uri, payload: cstring, callback: Callback, data: rawptr, token: ^c.ulong, error: ^LS_Error) -> bool ---
	LSCallCancel :: proc(handle: rawptr, token: c.ulong, error: ^LS_Error) -> bool ---
	LSMessageGetPayload :: proc(message: rawptr) -> cstring ---
	LSErrorInit :: proc(error: ^LS_Error) -> bool ---
	LSErrorFree :: proc(error: ^LS_Error) ---
}
foreign import glib "system:glib-2.0"
foreign glib {
	g_main_context_default :: proc() -> rawptr ---
	g_main_context_iteration :: proc(main_context: rawptr, may_block: c.int) -> c.int ---
}

bus: rawptr

start_bus :: proc(app_id: cstring) -> bool {
	error: LS_Error
	LSErrorInit(&error)
	defer LSErrorFree(&error)
	library := sdl.LoadObject("libluna-service2.so.3")
	if library == nil {fmt.eprintln("Luna library is unavailable"); return false}
	defer sdl.UnloadObject(library)
	// Older webOS uses separate public/private buses. Newer versions unify them.
	legacy := cast(LS_Register_Legacy)sdl.LoadFunction(library, "LSRegisterPubPriv")
	registered :=
		legacy(app_id, &bus, false, &error) if legacy != nil else LSRegister(app_id, &bus, &error)
	if !registered || !LSGmainContextAttach(bus, g_main_context_default(), &error) {
		fmt.eprintln("native bus initialization failed:", error.error_code, error.message)
		close_bus()
		return false
	}
	return true
}

close_bus :: proc() {
	if bus == nil {return}
	error: LS_Error
	LSErrorInit(&error)
	defer LSErrorFree(&error)
	LSUnregister(bus, &error)
	bus = nil
}

poll_services :: proc() {
	for g_main_context_iteration(nil, 0) != 0 {}
	poll_display()
}

uhd_reply: enum {
	Waiting,
	No,
	Yes,
}

uhd_callback :: proc "c" (_: rawptr, message: rawptr, _: rawptr) -> bool {
	context = runtime.default_context()
	uhd_reply = .No
	value, error := json.parse(string(LSMessageGetPayload(message)))
	if error != .None {return true}
	defer json.destroy_value(value)
	root, _ := value.(json.Object)
	if text, found := root["UHD"].(json.String); found && text == "true" {uhd_reply = .Yes}
	return true
}

// Ask the supported system property service whether the panel is UHD. Any
// failure or timeout keeps the conservative profile.
query_uhd_panel :: proc() -> bool {
	if bus == nil {return false}
	error: LS_Error
	LSErrorInit(&error)
	defer LSErrorFree(&error)
	token: c.ulong
	uhd_reply = .Waiting
	if !LSCallOneReply(
		bus,
		"luna://com.webos.service.tv.systemproperty/getSystemInfo",
		`{"keys":["UHD"]}`,
		uhd_callback,
		nil,
		&token,
		&error,
	) {return false}
	start := sdl.GetTicks()
	for uhd_reply == .Waiting && sdl.GetTicks() - start < 2000 {
		g_main_context_iteration(nil, 0)
		sdl.Delay(10)
	}
	if uhd_reply == .Waiting {LSCallCancel(bus, token, &error)}
	return uhd_reply == .Yes
}
