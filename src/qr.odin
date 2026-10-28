package main

import "core:c"

// qrcodegen_BUFFER_LEN_MAX: space for any QR code through version 40.
QR_Buffer :: [3918]u8

foreign qr {
	qrcodegen_encodeText :: proc(text: cstring, temp, code: ^QR_Buffer, ecc, min_version, max_version, mask: c.int, boost: bool) -> bool ---
	qrcodegen_getSize :: proc(code: ^QR_Buffer) -> c.int ---
	@(link_name = "qrcodegen_getModule")
	qr_module :: proc(code: ^QR_Buffer, x, y: c.int) -> bool ---
}

qr_encode :: proc(text: cstring, code: ^QR_Buffer) -> c.int {
	temp: QR_Buffer
	if !qrcodegen_encodeText(
		text,
		&temp,
		code,
		ecc = 1,
		min_version = 1,
		max_version = 40,
		mask = -1,
		boost = true,
	) {return 0}
	return qrcodegen_getSize(code)
}
