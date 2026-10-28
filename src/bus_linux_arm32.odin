package main

import "core:c"
import "core:fmt"

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

foreign import luna "system:luna-service2"
foreign luna {
	// The B9 uses the legacy public/private bus API.
	LSRegisterPubPriv :: proc(name: cstring, handle: ^rawptr, public_bus: bool, error: ^LS_Error) -> bool ---
	LSGmainContextAttach :: proc(handle, main_context: rawptr, error: ^LS_Error) -> bool ---
	LSUnregister :: proc(handle: rawptr, error: ^LS_Error) -> bool ---
	LSCall :: proc(handle: rawptr, uri, payload: cstring, callback: Callback, data: rawptr, token: ^c.ulong, error: ^LS_Error) -> bool ---
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
media_subscription: c.ulong

start_bus :: proc(app_id: cstring) -> bool {
	error: LS_Error
	LSErrorInit(&error)
	defer LSErrorFree(&error)
	if !LSRegisterPubPriv(app_id, &bus, false, &error) ||
	   !LSGmainContextAttach(bus, g_main_context_default(), &error) {
		fmt.eprintln("native bus initialization failed:", error.error_code, error.message)
		close_bus()
		return false
	}
	return true
}

cancel_media_subscription :: proc() {
	if bus == nil || media_subscription == 0 {return}
	error: LS_Error
	LSErrorInit(&error)
	defer LSErrorFree(&error)
	LSCallCancel(bus, media_subscription, &error)
	media_subscription = 0
}

close_bus :: proc() {
	if bus == nil {return}
	cancel_media_subscription()
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
