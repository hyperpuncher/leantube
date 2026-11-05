#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* The exported-window path is not exercised on the host. */
bool lt_export_window(void *display, void *surface) {
	(void)display;
	(void)surface;
	return false;
}
const char *lt_window_id(void) { return NULL; }
bool lt_set_window(int32_t source_width, int32_t source_height, int32_t destination_width,
				   int32_t destination_height) {
	(void)source_width;
	(void)source_height;
	(void)destination_width;
	(void)destination_height;
	return false;
}
void lt_unexport_window(void) {}
