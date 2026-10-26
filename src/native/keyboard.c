/*
  Based on SDL-webOS, contributed by Mariotaku <mariotaku.lee@gmail.com>.
  Modified for LeanTube: use public Wayland APIs and Odin input callbacks.

  Simple DirectMedia Layer
  Copyright (C) 1997-2023 Sam Lantinga <slouken@libsdl.org>

  This software is provided 'as-is', without any express or implied
  warranty. In no event will the authors be held liable for any damages
  arising from the use of this software.

  Permission is granted to anyone to use this software for any purpose,
  including commercial applications, and to alter it and redistribute it
  freely, subject to the following restrictions:

  1. The origin of this software must not be misrepresented; you must not
	 claim that you wrote the original software. If you use this software
	 in a product, an acknowledgment in the product documentation would be
	 appreciated but is not required.
  2. Altered source versions must be plainly marked as such, and must not be
	 misrepresented as being the original software.
  3. This notice may not be removed or altered from any source distribution.
*/
#include "keyboard.h"
#include "text-client-protocol.h"
#include <string.h>

static struct wl_display *display;
static struct wl_surface *surface;
static struct wl_seat *seat;
static struct text_model_factory *factory;
static struct text_model *model;
static tv_text_callback notify;
static uint32_t serial;
static bool active;

enum { TEXT_COMMIT = 1, TEXT_KEY, TEXT_DELETE, TEXT_CLOSED };

static void commit_text(void *data, struct text_model *m, uint32_t s, const char *text) {
	if (active)
		notify(TEXT_COMMIT, text, 0, 0);
}
static void preedit(void *data, struct text_model *m, uint32_t s, const char *text,
					const char *commit) {}
static void erase(void *data, struct text_model *m, uint32_t s, int32_t index, uint32_t length) {
	if (active)
		notify(TEXT_DELETE, "", index, length);
}
static void cursor(void *data, struct text_model *m, uint32_t s, int32_t index, int32_t anchor) {}
static void styling(void *data, struct text_model *m, uint32_t s, uint32_t index, uint32_t length,
					uint32_t style) {}
static void preedit_cursor(void *data, struct text_model *m, uint32_t s, int32_t index) {}
static void modifiers(void *data, struct text_model *m, struct wl_array *map) {}
static void keysym(void *data, struct text_model *m, uint32_t s, uint32_t time, uint32_t sym,
				   uint32_t state, uint32_t mods) {
	if (active && state == WL_KEYBOARD_KEY_STATE_PRESSED)
		notify(TEXT_KEY, "", (int32_t)sym, 0);
}
static void enter(void *data, struct text_model *m, struct wl_surface *window) {}
static void leave(void *data, struct text_model *m) {
	if (m != model)
		return;
	bool was_active = active;
	active = false;
	text_model_destroy(model);
	model = NULL;
	if (was_active)
		notify(TEXT_CLOSED, "", 0, 0);
}
static void panel_state(void *data, struct text_model *m, uint32_t state) {
	if (!state && active && m == model) {
		tv_keyboard_hide();
		notify(TEXT_CLOSED, "", 0, 0);
	}
}
static void panel_rect(void *data, struct text_model *m, int32_t x, int32_t y, uint32_t w,
					   uint32_t h) {}
static const struct text_model_listener listener = {
	.commit_string = commit_text,
	.preedit_string = preedit,
	.delete_surrounding_text = erase,
	.cursor_position = cursor,
	.preedit_styling = styling,
	.preedit_cursor = preedit_cursor,
	.modifiers_map = modifiers,
	.keysym = keysym,
	.enter = enter,
	.leave = leave,
	.input_panel_state = panel_state,
	.input_panel_rect = panel_rect,
};
static void capabilities(void *data, struct wl_seat *s, uint32_t caps) {}
static void seat_name(void *data, struct wl_seat *s, const char *name) {}
static const struct wl_seat_listener seat_listener = {capabilities, seat_name};

void tv_keyboard_registry(struct wl_registry *registry, uint32_t name, const char *interface) {
	if (!strcmp(interface, "text_model_factory"))
		factory = wl_registry_bind(registry, name, &text_model_factory_interface, 1);
	if (!seat && !strcmp(interface, "wl_seat")) {
		seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
		wl_seat_add_listener(seat, &seat_listener, NULL);
	}
}
void tv_keyboard_attach(struct wl_display *d, struct wl_surface *s) {
	display = d;
	surface = s;
}
bool tv_keyboard_show(tv_text_callback callback) {
	if (!factory || !seat || !surface)
		return false;
	if (!model) {
		model = text_model_factory_create_text_model(factory);
		if (!model)
			return false;
		text_model_add_listener(model, &listener, NULL);
	}
	notify = callback;
	active = true;
	text_model_activate(model, ++serial, seat, surface);
	text_model_set_content_type(model, TEXT_MODEL_CONTENT_HINT_NONE,
								TEXT_MODEL_CONTENT_PURPOSE_NORMAL);
	text_model_set_enter_key_type(model, TEXT_MODEL_ENTER_KEY_TYPE_SEARCH);
	text_model_set_max_text_length(model, 512);
	text_model_set_surrounding_text(model, "", 0, 0);
	wl_display_flush(display);
	return true;
}
void tv_keyboard_hide(void) {
	if (model) {
		if (active)
			text_model_deactivate(model, seat);
		active = false;
		text_model_destroy(model);
		model = NULL;
		wl_display_flush(display);
	}
}
void tv_keyboard_shutdown(void) {
	tv_keyboard_hide();
	if (factory)
		text_model_factory_destroy(factory);
	if (seat)
		wl_seat_destroy(seat);
	model = NULL;
	factory = NULL;
	seat = NULL;
	display = NULL;
	surface = NULL;
	notify = NULL;
}
