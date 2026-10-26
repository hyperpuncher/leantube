package main

foreign import bridge "system:tv_bridge"
foreign bridge {
	tv_qr_encode :: proc(text: cstring, qr: [^]u8) -> i32 ---
	tv_qr_module :: proc(qr: [^]u8, x, y: i32) -> bool ---
}

qr_encode :: proc(text: cstring, qr: [^]u8) -> i32 {
	return tv_qr_encode(text, qr)
}

qr_module :: proc(qr: [^]u8, x, y: i32) -> bool {
	return tv_qr_module(qr, x, y)
}
