/* Export only the generated inline Wayland helpers used by Odin. */
#include "text-client-protocol.h"
#include "webos-shell-client-protocol.h"

struct wl_registry *lt_wl_display_get_registry(struct wl_display *display) {
	return wl_display_get_registry(display);
}
void *lt_wl_registry_bind(struct wl_registry *registry, uint32_t name,
						  const struct wl_interface *interface, uint32_t version) {
	return wl_registry_bind(registry, name, interface, version);
}
struct wl_shell_surface *lt_wl_shell_get_shell_surface(struct wl_shell *shell,
													   struct wl_surface *surface) {
	return wl_shell_get_shell_surface(shell, surface);
}
void lt_wl_shell_surface_pong(struct wl_shell_surface *surface, uint32_t serial) {
	wl_shell_surface_pong(surface, serial);
}
void lt_wl_shell_surface_set_class(struct wl_shell_surface *surface, const char *name) {
	wl_shell_surface_set_class(surface, name);
}
void lt_wl_shell_surface_set_toplevel(struct wl_shell_surface *surface) {
	wl_shell_surface_set_toplevel(surface);
}
struct wl_webos_shell_surface *lt_wl_webos_shell_get_shell_surface(struct wl_webos_shell *shell,
																   struct wl_surface *surface) {
	return wl_webos_shell_get_shell_surface(shell, surface);
}
void lt_wl_webos_shell_surface_set_property(struct wl_webos_shell_surface *surface,
											const char *name, const char *value) {
	wl_webos_shell_surface_set_property(surface, name, value);
}
void lt_wl_webos_shell_surface_set_state(struct wl_webos_shell_surface *surface, uint32_t state) {
	wl_webos_shell_surface_set_state(surface, state);
}
struct text_model *lt_text_model_factory_create_text_model(struct text_model_factory *factory) {
	return text_model_factory_create_text_model(factory);
}
void lt_text_model_activate(struct text_model *model, uint32_t serial, struct wl_seat *seat,
							struct wl_surface *surface) {
	text_model_activate(model, serial, seat, surface);
}
void lt_text_model_deactivate(struct text_model *model, struct wl_seat *seat) {
	text_model_deactivate(model, seat);
}
void lt_text_model_set_content_type(struct text_model *model, uint32_t hint, uint32_t purpose) {
	text_model_set_content_type(model, hint, purpose);
}
void lt_text_model_set_enter_key_type(struct text_model *model, uint32_t type) {
	text_model_set_enter_key_type(model, type);
}
void lt_text_model_set_max_text_length(struct text_model *model, uint32_t length) {
	text_model_set_max_text_length(model, length);
}
void lt_text_model_set_surrounding_text(struct text_model *model, const char *text, uint32_t cursor,
										uint32_t anchor) {
	text_model_set_surrounding_text(model, text, cursor, anchor);
}
