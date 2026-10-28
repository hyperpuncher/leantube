package main

// Use the same QR library as the TV, without loading the webOS bridge.
foreign import qr "../build/host-qr/qrcodegen.a"
foreign qr {
	qrcodegen_encodeText :: proc(text: cstring, temp, code: [^]u8, ecc, min_version, max_version, mask: i32, boost: bool) -> bool ---
	qrcodegen_getSize :: proc(code: [^]u8) -> i32 ---
	@(link_name = "qrcodegen_getModule")
	qr_module :: proc(code: [^]u8, x, y: i32) -> bool ---
}

qr_encode :: proc(text: cstring, code: [^]u8) -> i32 {
	temp: [4096]u8
	if !qrcodegen_encodeText(text, raw_data(temp[:]), code, 1, 1, 40, -1, true) {return 0}
	return qrcodegen_getSize(code)
}
