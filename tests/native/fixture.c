#include <stdbool.h>
#include <stdio.h>

typedef void (*Acb_Callback)(long, long, long, long, long, const char *);
Acb_Callback ready_callback;
int metadata_calls, playing_calls, destroy_calls;
char applied_metadata[128];

/* Only the unavailable TV display API is replaced. */
long AcbAPI_create(void) { return 7; }
bool AcbAPI_initialize(long id, int type, const char *app, Acb_Callback callback) {
	(void)id;
	(void)type;
	(void)app;
	ready_callback = callback;
	return true;
}
bool AcbAPI_setMediaId(long id, const char *media) {
	(void)id;
	(void)media;
	return true;
}
int AcbAPI_setMediaVideoData(long id, const char *payload, long *task) {
	(void)id;
	(void)task;
	snprintf(applied_metadata, sizeof(applied_metadata), "%s", payload);
	metadata_calls++;
	return 1;
}
int AcbAPI_setState(long id, int app, int play, long *task) {
	(void)id;
	(void)app;
	(void)task;
	if (play == 2)
		playing_calls++;
	return 1;
}
int AcbAPI_setDisplayWindow(long id, long x, long y, long w, long h, bool full, long *task) {
	(void)id;
	(void)x;
	(void)y;
	(void)w;
	(void)h;
	(void)full;
	(void)task;
	return 1;
}
int AcbAPI_finalize(long id) {
	(void)id;
	return 1;
}
void AcbAPI_destroy(long id) {
	(void)id;
	destroy_calls++;
}
