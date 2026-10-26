package main

// The host preview does not load the TV bridge. Login rendering stays disabled
// until the ARM32 build supplies the real QR encoder.
qr_encode :: proc(_: cstring, _: [^]u8) -> i32 {
	return 0
}

qr_module :: proc(_: [^]u8, _, _: i32) -> bool {
	return false
}
