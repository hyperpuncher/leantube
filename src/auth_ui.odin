package main

import clay "../vendor/clay"
import yt "./youtube"
import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import sdl "vendor:sdl3"
import img "vendor:sdl3/image"

signed_in: bool
login_screen: bool
login_code: string
login_url: string
login_message: string
login_interval_ms: u64 = 5000
login_next_poll: u64
login_waiting: bool
login_add_account: bool
login_qr: ^sdl.Texture
account_menu: bool
account_menu_selected: int
account_avatar: ^sdl.Texture

account_initial :: proc() -> string {
	token := current_auth()
	if token == nil {return "?"}
	return account_initial_name(token.name)
}

set_account_avatar :: proc(renderer: ^sdl.Renderer, bytes: []u8) {
	if len(bytes) == 0 {return}
	io := sdl.IOFromConstMem(raw_data(bytes), uint(len(bytes)))
	if io == nil {return}
	texture := img.LoadTexture_IO(renderer, io, true)
	if texture == nil {return}
	_ = sdl.SetTextureBlendMode(texture, sdl.BLENDMODE_BLEND)
	_ = sdl.SetTextureScaleMode(texture, .LINEAR)
	if account_avatar != nil {sdl.DestroyTexture(account_avatar)}
	account_avatar = texture
}

start_login :: proc(add := false) {
	if login_screen || (signed_in && !add) {return}
	login_add_account = add
	login_screen = true
	login_waiting = true
	login_next_poll = 0
	delete(login_message)
	login_message = strings.clone("requesting a sign-in code…")
	dirty = true
	if !submit_network({kind = .Login_Start}) {
		login_waiting = false
		delete(login_message)
		login_message = strings.clone("could not start sign-in")
	}
}

poll_login_tick :: proc() {
	if !login_screen || login_waiting || login_next_poll == 0 {return}
	if sdl.GetTicks() < login_next_poll {return}
	login_waiting = true
	if !submit_network({kind = .Login_Poll}) {
		login_waiting = false
		login_next_poll = sdl.GetTicks() + login_interval_ms
	}
}

open_login_screen :: proc(code, url: string, interval: int) {
	login_screen = true
	login_waiting = false
	delete(login_code); login_code = strings.clone(code)
	delete(login_url); login_url = strings.clone(url)
	login_interval_ms = u64(max(interval, 1)) * 1000
	login_next_poll = sdl.GetTicks() + login_interval_ms
	delete(login_message)
	login_message = strings.clone("Waiting for approval…")
	if login_qr != nil {sdl.DestroyTexture(login_qr); login_qr = nil}
	dirty = true
}

close_login_screen :: proc() {
	if login_qr != nil {sdl.DestroyTexture(login_qr); login_qr = nil}
	delete(login_code); login_code = ""
	delete(login_url); login_url = ""
	delete(login_message); login_message = ""
	login_screen = false
	login_waiting = false
	login_next_poll = 0
	dirty = true
}

use_current_account :: proc() {
	account_menu = false
	if account_avatar != nil {sdl.DestroyTexture(account_avatar); account_avatar = nil}
	token := current_auth()
	signed_in = token != nil
	yt.set_access_token(signed_in ? token.access_token : "")
	if signed_in && token.avatar_url != "" {
		_ = submit_network({kind = .Avatar, text = strings.clone(token.avatar_url)})
	}
	dirty = true
}

sign_out :: proc() {
	clear_auth()
	use_current_account()
	notice = signed_in ? "account switched" : "signed out"
}

activate_account :: proc(index: int) {
	if index < 0 || index >= len(auth_accounts) {return}
	auth_active = index
	use_current_account()
	_ = save_auth()
	if catalog.query != "" {start_search(catalog.query)} else {start_search()}
}

account_initial_name :: proc(name: string) -> string {
	if name == "" {return "Y"}
	_, size := utf8.decode_rune_in_string(name)
	return name[:size]
}

ensure_login_qr :: proc(renderer: ^sdl.Renderer) -> bool {
	if login_qr != nil {return true}
	if login_code == "" || login_url == "" {return false}
	payload := fmt.aprintf(
		strings.contains(login_url, "?") ? "%s&user_code=%s" : "%s?user_code=%s",
		login_url,
		login_code,
	)
	defer delete(payload)
	qr := make([]u8, 4096)
	defer delete(qr)
	text := strings.clone_to_cstring(payload)
	defer delete(text)
	size := int(qr_encode(text, raw_data(qr)))
	if size <= 0 {return false}
	modules := size + 8
	scale := 8
	pixels := make([]u8, modules * modules * scale * scale * 4)
	defer delete(pixels)
	for y in 0 ..< modules {
		for x in 0 ..< modules {
			black :=
				x >= 4 &&
				y >= 4 &&
				x < 4 + size &&
				y < 4 + size &&
				qr_module(raw_data(qr), i32(x - 4), i32(y - 4))
			for py in 0 ..< scale {
				for px in 0 ..< scale {
					index := ((y * scale + py) * modules * scale + x * scale + px) * 4
					value := u8(black ? 0 : 255)
					pixels[index + 0] = value
					pixels[index + 1] = value
					pixels[index + 2] = value
					pixels[index + 3] = 255
				}
			}
		}
	}
	pixel_width := modules * scale
	surface := sdl.CreateSurfaceFrom(
		i32(pixel_width),
		i32(pixel_width),
		.RGBA32,
		raw_data(pixels),
		i32(pixel_width * 4),
	)
	if surface == nil {return false}
	defer sdl.DestroySurface(surface)
	login_qr = sdl.CreateTextureFromSurface(renderer, surface)
	if login_qr == nil {return false}
	_ = sdl.SetTextureScaleMode(login_qr, .NEAREST)
	return true
}

login_layout :: proc() {
	if clay.UI(clay.ID("login-root"))(
	{
		layout = {
			sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
			layoutDirection = .TopToBottom,
			childAlignment = {x = .Center, y = .Center},
			padding = clay.PaddingAll(spacing(48)),
		},
		backgroundColor = COLOR_BACKGROUND,
	},
	) {
		if clay.UI(clay.ID("login-card"))(
		{
			layout = {
				sizing = {width = clay.SizingFixed(scaled(560))},
				layoutDirection = .TopToBottom,
				childAlignment = {x = .Center, y = .Center},
				childGap = spacing(16),
				padding = clay.PaddingAll(spacing(36)),
			},
			backgroundColor = COLOR_SURFACE,
			cornerRadius = clay.CornerRadiusAll(scaled(24)),
		},
		) {
			label(
				login_add_account ? "Scan to add a YouTube account" : "Scan the QR to sign in to YouTube",
				.Heading,
			)
			if login_qr != nil {
				if clay.UI(clay.ID("login-qr"))(
				{
					layout = {
						sizing = {
							width = clay.SizingFixed(scaled(320)),
							height = clay.SizingFixed(scaled(320)),
						},
					},
					image = {imageData = rawptr(login_qr)},
					cornerRadius = clay.CornerRadiusAll(scaled(8)),
				},
				) {}
			} else {
				if clay.UI(clay.ID("login-waiting"))(
				{
					layout = {
						sizing = {
							width = clay.SizingFixed(scaled(320)),
							height = clay.SizingFixed(scaled(320)),
						},
					},
					backgroundColor = COLOR_BACKGROUND,
					cornerRadius = clay.CornerRadiusAll(scaled(8)),
				},
				) {}
			}
			if login_code != "" {label(login_code, .Heading, COLOR_ACCENT)}
			label("google.com/device", .Body, COLOR_MUTED)
			if login_message != "" {label(login_message, .Small, COLOR_MUTED)}
		}
	}
}

account_button :: proc(compact: bool = false) {
	color := clay.PointerOver(clay.ID("account")) ? COLOR_HOVER : COLOR_SURFACE
	width := signed_in || compact ? scaled(56) : scaled(168)
	if clay.UI(clay.ID("account"))(
	{
		layout = {
			sizing = {width = clay.SizingFixed(width), height = clay.SizingFixed(scaled(56))},
			childAlignment = {x = .Center, y = .Center},
		},
		backgroundColor = signed_in ? clay.Color{} : color,
		cornerRadius = clay.CornerRadiusAll(scaled(28)),
	},
	) {
		if signed_in {
			if account_avatar != nil {
				if clay.UI(clay.ID("account-avatar"))(
				{
					layout = {
						sizing = {
							width = clay.SizingFixed(scaled(56)),
							height = clay.SizingFixed(scaled(56)),
						},
					},
					image = {imageData = rawptr(account_avatar)},
					cornerRadius = clay.CornerRadiusAll(scaled(28)),
				},
				) {}
			} else {
				if clay.UI(clay.ID("account-initial"))(
				{
					layout = {
						sizing = {
							width = clay.SizingFixed(scaled(56)),
							height = clay.SizingFixed(scaled(56)),
						},
						childAlignment = {x = .Center, y = .Center},
					},
					backgroundColor = COLOR_PANEL,
					cornerRadius = clay.CornerRadiusAll(scaled(28)),
				},
				) {label(account_initial(), .Body)}
			}
		} else if compact {
			icon(.Account, 32)
		} else {
			label("Sign in", .Small)
		}
	}
}

account_menu_layout :: proc() {
	width := scaled(560)
	if clay.UI(clay.ID("account-menu"))(
	{
		layout = {
			sizing = {width = clay.SizingFixed(width)},
			layoutDirection = .TopToBottom,
			childGap = spacing(4),
			padding = clay.PaddingAll(spacing(12)),
		},
		backgroundColor = COLOR_SURFACE,
		cornerRadius = clay.CornerRadiusAll(scaled(16)),
		floating = {
			attachTo = .Root,
			attachment = {element = .CenterCenter, parent = .CenterCenter},
			zIndex = 10,
		},
	},
	) {
		label("Users", .Heading)
		for token, i in auth_accounts {
			selected := i == auth_active
			if clay.UI(clay.ID("account-row", u32(i)))(
			{
				layout = {
					sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(scaled(56))},
					childGap = spacing(12),
					childAlignment = {y = .Center},
					padding = clay.PaddingAll(spacing(8)),
				},
				backgroundColor = account_menu_selected == i ? COLOR_HOVER : COLOR_SURFACE,
				cornerRadius = clay.CornerRadiusAll(scaled(10)),
			},
			) {
				if clay.UI()(
				{
					layout = {
						sizing = {
							width = clay.SizingFixed(scaled(40)),
							height = clay.SizingFixed(scaled(40)),
						},
						childAlignment = {x = .Center, y = .Center},
					},
					backgroundColor = selected && account_avatar != nil ? clay.Color{} : COLOR_BACKGROUND,
					image = {imageData = selected ? rawptr(account_avatar) : nil},
					cornerRadius = clay.CornerRadiusAll(scaled(20)),
				},
				) {
					if !selected || account_avatar == nil {
						label(account_initial_name(token.name), .Small)
					}
				}
				if clay.UI()(
				{
					layout = {
						sizing = {
							width = clay.SizingGrow({}),
							height = clay.SizingFixed(scaled(40)),
						},
						childAlignment = {y = .Center},
					},
					clip = {horizontal = true, vertical = true},
				},
				) {label(token.name == "" ? "YouTube" : token.name, .Small)}
			}
		}
		if len(auth_accounts) < MAX_ACCOUNTS {
			if clay.UI(clay.ID("add-account"))(
			{
				layout = {
					sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(scaled(48))},
					childAlignment = {y = .Center},
					padding = clay.PaddingAll(spacing(8)),
				},
				backgroundColor = account_menu_selected == len(auth_accounts) ? COLOR_HOVER : COLOR_SURFACE,
				cornerRadius = clay.CornerRadiusAll(scaled(10)),
			},
			) {label("Add account", .Small, COLOR_MUTED)}
		}
		if clay.UI(clay.ID("sign-out"))(
		{
			layout = {
				sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(scaled(48))},
				childAlignment = {y = .Center},
				padding = clay.PaddingAll(spacing(8)),
			},
			backgroundColor = account_menu_selected == len(auth_accounts) + int(len(auth_accounts) < MAX_ACCOUNTS) ? COLOR_HOVER : COLOR_SURFACE,
			cornerRadius = clay.CornerRadiusAll(scaled(10)),
		},
		) {label("Sign out", .Small, COLOR_MUTED)}
	}
}
