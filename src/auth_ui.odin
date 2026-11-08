package main

import clay "../vendor/clay"
import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import sdl "vendor:sdl3"

signed_in: bool
login_screen: bool
login_code: string
login_url: string
login_message: string
login_interval_ms: u64 = 5000
login_next_poll: u64
login_waiting: bool
login_add_account: bool
login_retry_selected: bool
login_qr: ^sdl.Texture
account_menu: bool
account_menu_selected: int
account_avatars: [MAX_ACCOUNTS]^sdl.Texture

account_initial :: proc() -> string {
	token := current_auth()
	if token == nil {return "?"}
	return account_initial_name(token.name)
}

close_account_avatars :: proc() {
	for texture in account_avatars {if texture != nil {sdl.DestroyTexture(texture)}}
	account_avatars = {}
}

set_account_avatar :: proc(renderer: ^sdl.Renderer, surface: ^sdl.Surface, url: string) {
	if surface == nil || url == "" {return}
	// Match by URL, not the active account or an index saved before sign-out.
	for token, i in auth_accounts {
		if token.avatar_url != url {continue}
		texture := sdl.CreateTextureFromSurface(renderer, surface)
		if texture == nil {continue}
		_ = sdl.SetTextureBlendMode(texture, sdl.BLENDMODE_BLEND)
		_ = sdl.SetTextureScaleMode(texture, .LINEAR)
		if previous := account_avatars[i]; previous != nil {sdl.DestroyTexture(previous)}
		account_avatars[i] = texture
	}
}

start_login :: proc(add := false) {
	if login_screen || (signed_in && !add) {return}
	login_add_account = add
	login_retry_selected = false
	login_screen = true
	login_waiting = true
	login_next_poll = 0
	delete(login_message)
	login_message = strings.clone("Getting your sign-in code…")
	dirty = true
	if !submit_network({kind = .Login_Start}) {
		login_waiting = false
		delete(login_message)
		login_message = strings.clone("Could not get a sign-in code. Try again.")
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
	clear_browse_history()
	account_menu = false
	token := current_auth()
	signed_in = token != nil
	account_revision += 1
	_ = submit_network(
		{
			kind = .Use_Account,
			account = account_revision,
			auth_token = signed_in ? clone_auth_token(token^) : Auth_Token{},
		},
	)
	for saved, i in auth_accounts {
		if i == auth_active || saved.avatar_url == "" || account_avatars[i] != nil {continue}
		_ = submit_network({kind = .Account_Avatar, text = strings.clone(saved.avatar_url)})
	}
	dirty = true
}

sign_out :: proc() {
	close_account_avatars()
	clear_auth()
	use_current_account()
	if !signed_in {
		start_login()
		return
	}
	reload_feed()
}

activate_account :: proc(index: int) {
	if index < 0 || index >= len(auth_accounts) {return}
	auth_active = index
	use_current_account()
	_ = save_auth()
	reload_feed()
}

account_initial_name :: proc(name: string) -> string {
	if name == "" {return "Y"}
	_, size := utf8.decode_rune_in_string(name)
	return name[:size]
}

ensure_login_qr :: proc(renderer: ^sdl.Renderer) -> bool {
	if login_qr != nil {return true}
	if login_code == "" || login_url == "" {return false}
	payload := fmt.caprintf(
		strings.contains(login_url, "?") ? "%s&user_code=%s" : "%s?user_code=%s",
		login_url,
		login_code,
	)
	defer delete(payload)
	qr: QR_Buffer
	size := int(qr_encode(payload, &qr))
	if size <= 0 {return false}
	// Store one pixel per module. SDL scales the QR with nearest sampling.
	modules := size + 8
	pixels := make([][4]u8, modules * modules)
	defer delete(pixels)
	for y in 0 ..< modules {
		for x in 0 ..< modules {
			black :=
				x >= 4 &&
				y >= 4 &&
				x < 4 + size &&
				y < 4 + size &&
				qr_module(&qr, i32(x - 4), i32(y - 4))
			value := u8(black ? 0 : 255)
			pixels[y * modules + x] = {value, value, value, 255}
		}
	}
	surface := sdl.CreateSurfaceFrom(
		i32(modules),
		i32(modules),
		.RGBA32,
		raw_data(pixels),
		i32(modules * 4),
	)
	if surface == nil {return false}
	defer sdl.DestroySurface(surface)
	login_qr = sdl.CreateTextureFromSurface(renderer, surface)
	if login_qr == nil {return false}
	_ = sdl.SetTextureScaleMode(login_qr, .NEAREST)
	return true
}

// Back and the secondary action return to search for a signed-out user.
leave_login :: proc(window: ^sdl.Window) {
	close_login_screen()
	if !signed_in {edit_search(window)}
}

login_failed :: proc() -> bool {
	return !login_waiting && login_next_poll == 0
}

retry_login :: proc() {
	add := login_add_account
	close_login_screen()
	start_login(add)
}

login_layout :: proc() {
	width := min(scaled(1200), view_width - scaled(128))
	stacked := view_width < scaled(1000)
	qr_size := scaled(stacked ? 256 : 400)
	if clay.UI(clay.ID("login-root"))(
	{
		layout = {
			sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
			childAlignment = {x = .Center, y = .Center},
			padding = clay.PaddingAll(spacing(48)),
		},
		backgroundColor = COLOR_BACKGROUND,
	},
	) {
		if clay.UI(clay.ID("login-content"))(
		{
			layout = {
				sizing = {width = clay.SizingFixed(width)},
				layoutDirection = stacked ? .TopToBottom : .LeftToRight,
				childGap = spacing(stacked ? 32 : 96),
				childAlignment = {x = .Center, y = .Center},
			},
		},
		) {
			if clay.UI(clay.ID("login-instructions"))(
			{
				layout = {
					sizing = {width = clay.SizingGrow({})},
					layoutDirection = .TopToBottom,
					childGap = spacing(stacked ? 16 : 24),
				},
			},
			) {
				label(
					login_add_account ? "Add your account" : "Sign in to YouTube",
					.Title,
					wrap = .Words,
				)
				label(
					"Your subscriptions and saved videos, ready to watch.",
					.Small,
					COLOR_MUTED,
					.Words,
				)
				if clay.UI()(
				{
					layout = {
						sizing = {width = clay.SizingGrow({})},
						layoutDirection = .TopToBottom,
						childGap = spacing(12),
						padding = padding(0, 0, 12, 12),
					},
				},
				) {
					label("Scan the QR code with your phone.", .Body, wrap = .Words)
					label("Or open the link and enter this code:", .Small, COLOR_MUTED, .Words)
					label("google.com/device", .Body)
					if clay.UI(clay.ID("login-code"))(
					{
						layout = {
							sizing = {height = clay.SizingFixed(scaled(52))},
							childAlignment = {y = .Center},
						},
					},
					) {
						if login_code != "" {label(login_code, .Body)}
					}
				}
				if clay.UI()(
				{
					layout = {
						layoutDirection = .TopToBottom,
						childGap = spacing(12),
						sizing = {width = clay.SizingGrow({})},
					},
				},
				) {
					login_action(
						"login-search",
						signed_in ? "Cancel" : "Search without signing in",
						!login_retry_selected,
					)
					if login_failed() {
						login_action("login-retry", "Try again", login_retry_selected)
					}
				}
				label(
					signed_in ? "Press Back to cancel" : "Press Back to search without an account",
					.Caption,
					COLOR_MUTED,
				)
			}
			if clay.UI(clay.ID("login-scan"))(
			{
				layout = {
					sizing = {width = clay.SizingFixed(qr_size)},
					layoutDirection = .TopToBottom,
					childGap = spacing(24),
					childAlignment = {x = .Center},
				},
			},
			) {
				if clay.UI(clay.ID("login-qr-frame"))(
				{
					layout = {
						sizing = {
							width = clay.SizingFixed(qr_size),
							height = clay.SizingFixed(qr_size),
						},
						childAlignment = {x = .Center, y = .Center},
						padding = clay.PaddingAll(spacing(16)),
					},
					backgroundColor = login_qr != nil ? clay.Color{255, 255, 255, 255} : COLOR_SURFACE,
					cornerRadius = clay.CornerRadiusAll(scaled(24)),
				},
				) {
					if login_qr != nil {
						if clay.UI(clay.ID("login-qr"))(
						{
							layout = {
								sizing = {
									width = clay.SizingFixed(qr_size - scaled(32)),
									height = clay.SizingFixed(qr_size - scaled(32)),
								},
							},
							image = {imageData = rawptr(login_qr)},
						},
						) {}
					} else if !login_failed() {
						icon(.Spinner)
					} else {icon(.Account, 64)}
				}
				if clay.UI(clay.ID("login-status"))(
				{
					layout = {
						sizing = {
							width = clay.SizingGrow({}),
							height = clay.SizingFixed(scaled(64)),
						},
						childAlignment = {x = .Center, y = .Top},
						childGap = spacing(12),
					},
				},
				) {
					if login_code != "" && !login_failed() {icon(.Spinner, 24)}
					label(login_message, .Caption, COLOR_MUTED, .Words)
				}
			}
		}
	}
}

login_action :: proc(id, text: string, selected: bool) {
	active := selected || clay.PointerOver(clay.ID(id))
	if clay.UI(clay.ID(id))(
	{
		layout = {
			sizing = {height = clay.SizingFixed(scaled(64))},
			padding = padding(24, 24, 0, 0),
			childAlignment = {x = .Center, y = .Center},
		},
		backgroundColor = active ? COLOR_TEXT : COLOR_SURFACE,
		cornerRadius = clay.CornerRadiusAll(scaled(32)),
	},
	) {label(text, .Small, active ? COLOR_BACKGROUND : COLOR_TEXT)}
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
			avatar := current_auth() != nil ? account_avatars[auth_active] : nil
			if avatar != nil {
				if clay.UI(clay.ID("account-avatar"))(
				{
					layout = {
						sizing = {
							width = clay.SizingFixed(scaled(56)),
							height = clay.SizingFixed(scaled(56)),
						},
					},
					image = {imageData = rawptr(avatar)},
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
	if clay.UI(clay.ID("account-scrim"))(
	{
		layout = {
			sizing = {
				width = clay.SizingFixed(view_width),
				height = clay.SizingFixed(view_height),
			},
		},
		backgroundColor = {0, 0, 0, 160},
		floating = {attachTo = .Root, zIndex = 10},
	},
	) {}
	width := min(scaled(640), view_width - scaled(64))
	if clay.UI(clay.ID("account-menu"))(
	{
		layout = {
			sizing = {width = clay.SizingFixed(width)},
			layoutDirection = .TopToBottom,
			childGap = spacing(8),
			padding = clay.PaddingAll(spacing(24)),
		},
		backgroundColor = COLOR_SURFACE,
		cornerRadius = clay.CornerRadiusAll(scaled(24)),
		floating = {
			attachTo = .Root,
			attachment = {element = .CenterCenter, parent = .CenterCenter},
			zIndex = 11,
		},
	},
	) {
		if clay.UI()(
		{
			layout = {
				layoutDirection = .TopToBottom,
				childGap = spacing(4),
				padding = padding(12, 12, 4, 16),
			},
		},
		) {
			label("Accounts", .Heading)
			label("Choose a YouTube account", .Small, COLOR_MUTED)
		}
		for token, i in auth_accounts {
			selected := i == auth_active
			avatar := account_avatars[i]
			if clay.UI(clay.ID("account-row", u32(i)))(
			{
				layout = {
					sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(scaled(88))},
					childGap = spacing(16),
					childAlignment = {y = .Center},
					padding = clay.PaddingAll(spacing(12)),
				},
				backgroundColor = account_menu_selected == i ? COLOR_HOVER : COLOR_SURFACE,
				cornerRadius = clay.CornerRadiusAll(scaled(10)),
			},
			) {
				if clay.UI()(
				{
					layout = {
						sizing = {
							width = clay.SizingFixed(scaled(64)),
							height = clay.SizingFixed(scaled(64)),
						},
						childAlignment = {x = .Center, y = .Center},
					},
					backgroundColor = avatar != nil ? clay.Color{} : COLOR_BACKGROUND,
					image = {imageData = rawptr(avatar)},
					cornerRadius = clay.CornerRadiusAll(scaled(32)),
				},
				) {
					if avatar == nil {
						label(account_initial_name(token.name), .Small)
					}
				}
				if clay.UI()(
				{
					layout = {
						sizing = {
							width = clay.SizingGrow({}),
							height = clay.SizingFixed(scaled(64)),
						},
						childAlignment = {y = .Center},
					},
					clip = {horizontal = true, vertical = true},
				},
				) {label(token.name == "" ? "YouTube" : token.name, .Body)}
				if selected {
					if clay.UI()(
					{
						layout = {padding = padding(12, 12, 6, 6)},
						backgroundColor = COLOR_BACKGROUND,
						cornerRadius = clay.CornerRadiusAll(scaled(8)),
					},
					) {label("Active", .Caption, COLOR_MUTED)}
				}
			}
		}
		if clay.UI()(
		{
			layout = {
				sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(scaled(1))},
			},
			backgroundColor = COLOR_TRACK,
		},
		) {}
		if len(auth_accounts) < MAX_ACCOUNTS {
			if clay.UI(clay.ID("add-account"))(
			{
				layout = {
					sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(scaled(64))},
					childAlignment = {y = .Center},
					padding = padding(16, 16, 8, 8),
				},
				backgroundColor = account_menu_selected == len(auth_accounts) ? COLOR_HOVER : COLOR_SURFACE,
				cornerRadius = clay.CornerRadiusAll(scaled(10)),
			},
			) {label("Add account", .Small)}
		}
		if clay.UI(clay.ID("sign-out"))(
		{
			layout = {
				sizing = {width = clay.SizingGrow({}), height = clay.SizingFixed(scaled(64))},
				childAlignment = {y = .Center},
				padding = padding(16, 16, 8, 8),
			},
			backgroundColor = account_menu_selected == len(auth_accounts) + int(len(auth_accounts) < MAX_ACCOUNTS) ? COLOR_HOVER : COLOR_SURFACE,
			cornerRadius = clay.CornerRadiusAll(scaled(10)),
		},
		) {label("Sign out", .Small, COLOR_MUTED)}
	}
}
