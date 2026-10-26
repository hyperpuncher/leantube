#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <wayland-client.h>

typedef void (*tv_text_callback)(uint32_t event, const char *text, int32_t index, uint32_t length);

void tv_keyboard_registry(struct wl_registry *, uint32_t name, const char *interface);
void tv_keyboard_attach(struct wl_display *, struct wl_surface *);
bool tv_keyboard_show(tv_text_callback);
void tv_keyboard_hide(void);
void tv_keyboard_shutdown(void);
