/* Export a window for the video plane on webOS 5 and later.
 *
 * The platform stopped shipping libAcbAPI there. The equivalent is a
 * webos_foreign exported window: the compositor returns an id, and the media
 * pipeline draws the video into that region. */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <wayland-client.h>

#include "webos-foreign-client-protocol.h"

static struct wl_compositor *compositor;
static struct wl_webos_foreign *foreign;
static struct wl_webos_exported *exported;
static char window_id[64];

static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
							const char *interface, uint32_t version) {
	(void)data;
	if (strcmp(interface, "wl_compositor") == 0) {
		compositor = wl_registry_bind(registry, name, &wl_compositor_interface, version);
	} else if (strcmp(interface, "wl_webos_foreign") == 0) {
		foreign = wl_registry_bind(registry, name, &wl_webos_foreign_interface, version);
	}
}

static void registry_remove(void *data, struct wl_registry *registry, uint32_t name) {
	(void)data;
	(void)registry;
	(void)name;
}

static const struct wl_registry_listener registry_listener = {registry_global, registry_remove};

static void window_id_assigned(void *data, struct wl_webos_exported *window, const char *id,
							   uint32_t type) {
	(void)data;
	(void)window;
	(void)type;
	snprintf(window_id, sizeof window_id, "%s", id);
}

static const struct wl_webos_exported_listener exported_listener = {window_id_assigned};

bool lt_export_window(struct wl_display *display, struct wl_surface *surface) {
	if (display == NULL || surface == NULL)
		return false;
	window_id[0] = '\0';
	if (foreign == NULL) {
		struct wl_registry *registry = wl_display_get_registry(display);
		if (registry == NULL)
			return false;
		wl_registry_add_listener(registry, &registry_listener, NULL);
		bool found = wl_display_roundtrip(display) >= 0 && compositor != NULL && foreign != NULL;
		wl_registry_destroy(registry);
		if (!found)
			return false;
	}
	exported = wl_webos_foreign_export_element(foreign, surface,
											   WL_WEBOS_FOREIGN_WEBOS_EXPORTED_TYPE_VIDEO_OBJECT);
	if (exported == NULL)
		return false;
	wl_webos_exported_add_listener(exported, &exported_listener, NULL);
	/* The id only arrives as an event, so wait for it before returning. */
	for (int attempt = 0; attempt < 10 && window_id[0] == '\0'; attempt++) {
		if (wl_display_roundtrip(display) < 0)
			break;
	}
	return window_id[0] != '\0';
}

const char *lt_window_id(void) { return window_id[0] == '\0' ? NULL : window_id; }

bool lt_set_window(int32_t source_width, int32_t source_height, int32_t destination_width,
				   int32_t destination_height) {
	if (exported == NULL || compositor == NULL)
		return false;
	struct wl_region *source = wl_compositor_create_region(compositor);
	struct wl_region *destination = wl_compositor_create_region(compositor);
	if (source == NULL || destination == NULL) {
		if (source != NULL)
			wl_region_destroy(source);
		if (destination != NULL)
			wl_region_destroy(destination);
		return false;
	}
	wl_region_add(source, 0, 0, source_width, source_height);
	wl_region_add(destination, 0, 0, destination_width, destination_height);
	wl_webos_exported_set_exported_window(exported, source, destination);
	wl_region_destroy(source);
	wl_region_destroy(destination);
	return true;
}

void lt_unexport_window(void) {
	if (exported != NULL) {
		wl_webos_exported_destroy(exported);
		exported = NULL;
	}
	window_id[0] = '\0';
}
