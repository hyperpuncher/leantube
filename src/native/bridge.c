#include "webos-shell-client-protocol.h"
#include <appswitching-control-block/AcbAPI.h>
#include <fcntl.h>
#include <glib.h>
#include <luna-service2/lunaservice.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>

/* This legacy public-bus API is present in the B9 firmware. */
extern bool LSRegisterPubPriv(const char *, LSHandle **, bool, LSError *);
/* The B9 entry point takes a task output pointer. The SDK omits this argument. */
extern int b9_set_media_video_data(long, const char *, long *) __asm__("AcbAPI_setMediaVideoData");

static struct wl_registry *registry;
static struct wl_webos_shell *shell;
static struct wl_webos_shell_surface *shell_surface;
static struct wl_shell *role_shell;
static struct wl_shell_surface *role_surface;
static struct wl_display *display;
static LSHandle *bus;
static GMainLoop *loop;
static LSMessageToken media_subscription;
static bool closing;
static bool visible = true;
static long acb_id = -1;
static gint display_ready;
static char *pending_video_data;

static void media_display_event(long id, long task, long event, long app_state, long play_state,
								const char *reply) {
	(void)reply;
	fprintf(stderr, "display event id=%ld task=%ld event=%ld app=%ld play=%ld\n", id, task, event,
			app_state, play_state);
	if (event == 1 && app_state == APPSTATE_FOREGROUND && play_state == PLAYSTATE_LOADED) {
		g_atomic_int_set(&display_ready, 1);
	}
}

bool tv_attach_media(const char *app_id, const char *media_id, const char *video_data) {
	pending_video_data = g_strdup(video_data);
	acb_id = AcbAPI_create();
	fprintf(stderr, "display control created id=%ld\n", acb_id);
	if (acb_id < 0 || !AcbAPI_initialize(acb_id, PLAYER_TYPE_VIDEO, app_id, media_display_event)) {
		fprintf(stderr, "display control initialization failed\n");
		return false;
	}
	bool bound = AcbAPI_setMediaId(acb_id, media_id);
	long task = 0;
	int loaded = AcbAPI_setState(acb_id, APPSTATE_FOREGROUND, PLAYSTATE_LOADED, &task);
	int window = AcbAPI_setDisplayWindow(acb_id, 0, 0, 1920, 1080, true, &task);
	fprintf(stderr, "display bind=%d loaded=%d window=%d\n", bound, loaded, window);
	return bound;
}

typedef bool (*reply_callback)(void *, void *, void *);

static void registry_add(void *data, struct wl_registry *reg, uint32_t name, const char *interface,
						 uint32_t version) {
	(void)data;
	(void)version;
	if (!strcmp(interface, "wl_shell")) {
		role_shell = wl_registry_bind(reg, name, &wl_shell_interface, 1);
	}
	if (!strcmp(interface, "wl_webos_shell")) {
		shell = wl_registry_bind(reg, name, &wl_webos_shell_interface, 1);
	}
}
static void registry_remove(void *data, struct wl_registry *reg, uint32_t name) {
	(void)data;
	(void)reg;
	(void)name;
}
static const struct wl_registry_listener registry_listener = {registry_add, registry_remove};

/* Match the wl_shell role used by SDL-webOS. The LG shell adds properties. */
static void role_ping(void *data, struct wl_shell_surface *surface, uint32_t serial) {
	(void)data;
	wl_shell_surface_pong(surface, serial);
}
static void role_configure(void *data, struct wl_shell_surface *surface, uint32_t edges,
						   int32_t width, int32_t height) {
	(void)data;
	(void)surface;
	(void)edges;
	(void)width;
	(void)height;
}
static void role_popup_done(void *data, struct wl_shell_surface *surface) {
	(void)data;
	(void)surface;
}
static const struct wl_shell_surface_listener role_listener = {role_ping, role_configure,
															   role_popup_done};

static void state_changed(void *data, struct wl_webos_shell_surface *surface, uint32_t state) {
	(void)data;
	(void)surface;
	visible = state != WL_WEBOS_SHELL_SURFACE_STATE_MINIMIZED;
	fprintf(stderr, "window state: %u\n", state);
}
static void position_changed(void *data, struct wl_webos_shell_surface *surface, int32_t x,
							 int32_t y) {
	(void)data;
	(void)surface;
	(void)x;
	(void)y;
}
static void close_requested(void *data, struct wl_webos_shell_surface *surface) {
	(void)data;
	(void)surface;
	closing = true;
}
static void exposed(void *data, struct wl_webos_shell_surface *surface,
					struct wl_array *rectangles) {
	(void)data;
	(void)surface;
	(void)rectangles;
}
static void state_changing(void *data, struct wl_webos_shell_surface *surface, uint32_t state) {
	(void)data;
	(void)surface;
	(void)state;
}
static const struct wl_webos_shell_surface_listener shell_listener = {
	state_changed, position_changed, close_requested, exposed, state_changing};

bool tv_bus_start(const char *app_id) {
	int log = open("/tmp/leantube.log", O_WRONLY | O_CREAT | O_TRUNC, 0600);
	if (log >= 0) {
		dup2(log, 1);
		dup2(log, 2);
		close(log);
	}
	FILE *pid_file = fopen("/tmp/leantube.pid", "w");
	if (pid_file) {
		fprintf(pid_file, "%ld\n", (long)getpid());
		fclose(pid_file);
	}
	LSError error;
	LSErrorInit(&error);
	loop = g_main_loop_new(NULL, false);
	if (!loop || !LSRegisterPubPriv(app_id, &bus, false, &error) ||
		!LSGmainAttach(bus, loop, &error)) {
		fprintf(stderr, "native bus initialization failed\n");
		LSErrorPrint(&error, stderr);
		LSErrorFree(&error);
		return false;
	}
	return true;
}

bool tv_send(const char *uri, const char *payload, reply_callback callback, void *data) {
	LSError error;
	LSErrorInit(&error);
	LSMessageToken token = 0;
	if (!LSCall(bus, uri, payload, (LSFilterFunc)callback, data, &token, &error)) {
		fprintf(stderr, "native service call failed: %s\n", uri);
		LSErrorFree(&error);
		return false;
	}
	if (!strcmp(uri, "luna://com.webos.media/subscribe"))
		media_subscription = token;
	return true;
}

const char *tv_payload(void *message) { return LSMessageGetPayload(message); }
void tv_poll(void) {
	while (g_main_context_iteration(NULL, false)) {
	}
	/* ACB callbacks run on its worker. Call its API here, not from that callback. */
	if (pending_video_data && acb_id >= 0 && g_atomic_int_get(&display_ready)) {
		long task = 0;
		int metadata = b9_set_media_video_data(acb_id, pending_video_data, &task);
		fprintf(stderr, "display metadata accepted=%d task=%ld\n", metadata, task);
		g_clear_pointer(&pending_video_data, g_free);
		int playing = AcbAPI_setState(acb_id, APPSTATE_FOREGROUND, PLAYSTATE_PLAYING, &task);
		fprintf(stderr, "display playing accepted=%d task=%ld\n", playing, task);
	}
}
bool tv_closing(void) { return closing; }
bool tv_visible(void) { return visible; }

bool tv_attach_window(const char *app_id, struct wl_display *window_display,
					  struct wl_surface *surface) {
	display = window_display;
	if (!display || !surface)
		return false;
	registry = wl_display_get_registry(display);
	wl_registry_add_listener(registry, &registry_listener, NULL);
	if (wl_display_roundtrip(display) < 0 || !shell || !role_shell) {
		fprintf(stderr, "LG window role is unavailable\n");
		return false;
	}
	role_surface = wl_shell_get_shell_surface(role_shell, surface);
	if (!role_surface)
		return false;
	wl_shell_surface_add_listener(role_surface, &role_listener, NULL);
	wl_shell_surface_set_class(role_surface, app_id);
	wl_shell_surface_set_toplevel(role_surface);
	shell_surface = wl_webos_shell_get_shell_surface(shell, surface);
	if (!shell_surface)
		return false;
	wl_webos_shell_surface_add_listener(shell_surface, &shell_listener, NULL);
	wl_webos_shell_surface_set_property(shell_surface, "appId", app_id);
	wl_webos_shell_surface_set_property(shell_surface, "_WEBOS_ACCESS_POLICY_KEYS_BACK", "true");
	wl_webos_shell_surface_set_state(shell_surface, WL_WEBOS_SHELL_SURFACE_STATE_FULLSCREEN);
	wl_display_flush(display);
	return true;
}

void tv_raise(void) {
	if (shell_surface) {
		wl_webos_shell_surface_set_state(shell_surface, WL_WEBOS_SHELL_SURFACE_STATE_FULLSCREEN);
		wl_display_flush(display);
	}
}

void tv_release_media(void) {
	if (bus && media_subscription) {
		LSError error;
		LSErrorInit(&error);
		LSCallCancel(bus, media_subscription, &error);
		LSErrorFree(&error);
		media_subscription = 0;
	}
	g_clear_pointer(&pending_video_data, g_free);
	if (acb_id >= 0) {
		long task = 0;
		AcbAPI_setState(acb_id, APPSTATE_BACKGROUND, PLAYSTATE_UNLOADED, &task);
		AcbAPI_finalize(acb_id);
		AcbAPI_destroy(acb_id);
		acb_id = -1;
	}
	g_atomic_int_set(&display_ready, 0);
}

void tv_shutdown(void) {
	tv_release_media();
	if (bus) {
		LSError error;
		LSErrorInit(&error);
		LSUnregister(bus, &error);
		LSErrorFree(&error);
		bus = NULL;
	}
	if (loop) {
		g_main_loop_unref(loop);
		loop = NULL;
	}
	if (shell_surface) {
		wl_webos_shell_surface_destroy(shell_surface);
		shell_surface = NULL;
	}
	if (role_surface) {
		wl_shell_surface_destroy(role_surface);
		role_surface = NULL;
	}
	if (role_shell) {
		wl_shell_destroy(role_shell);
		role_shell = NULL;
	}
	if (shell) {
		wl_webos_shell_destroy(shell);
		shell = NULL;
	}
	if (registry) {
		wl_registry_destroy(registry);
		registry = NULL;
	}
}
