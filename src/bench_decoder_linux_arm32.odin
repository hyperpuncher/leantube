package main

import diagnostics "../tests/playback/diagnostics"
import reader "./playback"
import "core:c"
import queue "core:container/queue"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:sys/posix"
import "core:time"
import curl "vendor:curl"
import sdl "vendor:sdl3"

when PLAYBACK_BENCH {
	decoder_entry :: proc(args: []string) -> (result: int) {
		stage := 0
		defer fmt.eprintf("reader decoder initialization_stage=%d exit=%d\n", stage, result)
		o, valid := diagnostics.parse_options(args)
		if !valid {return 2}
		stage = 1
		o.receive_buffer_bytes, valid = diagnostics.receive_buffer_setting()
		if !valid {return 2}
		stage = 2
		o.decoder_preroll = true
		input, input_error := os.read_entire_file(os.stdin, context.allocator)
		if input_error != nil {return 2}
		defer delete(input)
		links := strings.split(string(input), "\n")
		defer delete(links)
		if len(links) < 2 {return 2}
		stage = 3
		if curl.global_init(c.long(curl.GLOBAL_DEFAULT)) != .E_OK {return 3}
		defer curl.global_cleanup()
		action := posix.sigaction_t {
			sa_handler = stop_signal,
		}
		if posix.sigaction(.SIGTERM, &action, nil) != .OK ||
		   posix.sigaction(.SIGINT, &action, nil) != .OK {return 3}
		_ = sdl.SetHint(sdl.HINT_VIDEO_DRIVER, "wayland")
		_ = sdl.SetAppMetadata("LeanTube", APP_VERSION, APP_ID)
		path, path_error := os.get_executable_path(context.allocator)
		if path_error != nil {return 3}
		defer delete(path)
		app_directory = filepath.dir(path)
		alias := fmt.aprintf("%s/lib/libwayland-egl.so.1", app_directory)
		defer delete(alias)
		if !os.exists(alias) &&
		   os.exists(
			   "/usr/lib/libwayland-egl.so.0",
		   ) {if os.symlink("/usr/lib/libwayland-egl.so.0", alias) != nil {return 3}}
		stage = 4
		if !start_bus(APP_ID) {return 3}
		defer close_bus()
		// This explicit SSH diagnostic is not launched by the app manager.
		// The normal app keeps its managed lifecycle. Here the Wayland shell
		// owns the visible window and SIGTERM/Back perform orderly cleanup.
		if os.set_env("EGL_PLATFORM", "wayland") != nil ||
		   os.set_env("XDG_RUNTIME_DIR", "/tmp/xdg") != nil {return 3}
		stage = 42
		if !sdl.Init({.VIDEO}) {return 3}
		defer sdl.Quit()
		stage = 5
		window := create_window()
		if window == nil {return 3}
		defer sdl.DestroyWindow(window)
		props := sdl.GetWindowProperties(window)
		if !attach_window(
			APP_ID,
			sdl.GetPointerProperty(props, sdl.PROP_WINDOW_WAYLAND_DISPLAY_POINTER, nil),
			sdl.GetPointerProperty(props, sdl.PROP_WINDOW_WAYLAND_SURFACE_POINTER, nil),
		) {return 3}
		defer close_window()
		renderer := sdl.CreateRenderer(window, "opengles2")
		if renderer == nil {return 3}
		defer sdl.DestroyRenderer(renderer)
		_ = sdl.SetRenderDrawColor(renderer, 0, 0, 0, 0)
		_ = sdl.RenderClear(renderer)
		_ = sdl.RenderPresent(renderer)
		stage = 6
		session := reader.open(links[0], links[1], o.reader)
		if session == nil {return 3}
		defer reader.close(session)
		s := &session.state
		tracks := &session.tracks
		api: ^Starfish
		status: ^Decoder_Status
		defer if api != nil {if !decoder_close(api, status) {result = 1}}
		begun := time.tick_now()
		clock, played, report_at := o.start, f64(0), f64(0)
		paused, seek_done, bound := false, false, false
		buffering := false
		rebuffers := 0
		last_frame, last_play_attempt := f64(-1), f64(-1)
		startup := f64(-1)
		max_video, max_audio := f64(0), f64(0)
		failure := false
		for reader.seconds_since(begun) < f64(o.seconds) + 90 &&
		    sync.atomic_load(&interrupted) == 0 &&
		    running &&
		    !window_closing {
			poll_services()
			event: sdl.Event
			for sdl.PollEvent(&event) {
				if event.type == .QUIT ||
				   event.type == .WINDOW_CLOSE_REQUESTED {sync.atomic_store(&interrupted, 1)}
				if event.type == .KEY_DOWN && !event.key.repeat {
					code := input_key(event.key.raw, event.key.key)
					if code == sdl.K_ESCAPE ||
					   code == sdl.K_AC_BACK {sync.atomic_store(&interrupted, 1)}
					if code == sdl.K_SPACE ||
					   code == sdl.K_MEDIA_PLAY ||
					   code == sdl.K_MEDIA_PAUSE {
						paused = code == sdl.K_MEDIA_PAUSE || (code == sdl.K_SPACE && !paused)
						if api != nil {if paused {sf_pause(api)} else if !buffering {sf_play(api)}}
						fmt.printf("{{\"event\":\"decoder_pause\",\"paused\":%v}}\n", paused)
					}
				}
			}
			if sync.atomic_load(&s.failure) != 0 {failure = true; break}
			v, a := &tracks[0], &tracks[1]
			sync.mutex_lock(&v.mutex); sync.mutex_lock(&a.mutex)
			vb, ab := reader.ahead(v, clock), reader.ahead(a, clock)
			ready :=
				(vb >= reader.STARTUP_SECONDS || v.eof) &&
				(ab >= reader.STARTUP_SECONDS || a.eof) &&
				queue.len(v.packets) > 0 &&
				queue.len(a.packets) > 0
			max_video, max_audio = max(max_video, vb), max(max_audio, ab)
			end_of_input := v.eof || a.eof
			sync.mutex_unlock(&a.mutex); sync.mutex_unlock(&v.mutex)
			wall := reader.seconds_since(begun)
			if api == nil && ready {
				api, status = decoder_open(v, a, clock)
				if api == nil {failure = true; break}
				bound = false; last_play_attempt = -1
			}
			if api != nil {
				if sync.atomic_load(&status.error) != 0 {failure = true; break}
				if sync.atomic_load(&status.loaded) != 0 && !bound {
					task: c.long
					AcbAPI_setSinkType(acb_id, 0)
					AcbAPI_setState(acb_id, .Foreground, .Loaded, &task)
					bound = true
				}
				if !buffering &&
				   !paused &&
				   last_frame >= 0 &&
				   min(vb, ab) < 0.05 &&
				   !end_of_input {
					if !sf_pause(api) {failure = true; break}
					buffering = true
					rebuffers += 1
				}
				if buffering && ready {buffering = false}
				if !paused && !buffering {
					if !decoder_feed(api, a, clock + 1) ||
					   !decoder_feed(api, v, clock + 1) {failure = true; break}
					if wall - last_play_attempt > 0.25 &&
					   sync.atomic_load(&status.playing) ==
						   0 {sf_play(api); last_play_attempt = wall}
				}
				frame := sync.atomic_load(&status.frame_ns)
				if frame >= 0 {
					next := max(f64(frame) / 1e9, seek_done ? o.seek_to : o.start)
					if last_frame >= 0 &&
					   !paused &&
					   !buffering {played += max(0, next - last_frame)}
					last_frame = next; clock = max(clock, next)
					sync.atomic_store(&s.position, clock)
					for &t in tracks {sync.mutex_lock(&t.mutex); sync.cond_signal(&t.changed); sync.mutex_unlock(&t.mutex)}
					if startup < 0 {startup = wall}
				}
			}
			if !seek_done && o.seek_after >= 0 && played >= o.seek_after {
				if api != nil && !decoder_close(api, status) {api = nil; failure = true; break}
				api = nil; status = nil; last_frame = -1
				clock = o.seek_to; seek_done = true; buffering = false
				reader.seek(session, clock)
				fmt.printf("{{\"event\":\"decoder_seek\",\"target_s\":%.3f}}\n", clock)
			}
			if wall >= report_at {
				fmt.printf(
					"{{\"event\":\"decoder_progress\",\"wall_s\":%.3f,\"position_s\":%.3f,\"played_s\":%.3f,\"video_buffer_s\":%.3f,\"audio_buffer_s\":%.3f,\"presentation_updates\":%d,\"paused\":%v,\"buffering\":%v,\"rebuffers\":%d,\"native_pts_s\":%.3f}}\n",
					wall,
					clock,
					played,
					vb,
					ab,
					status == nil ? 0 : sync.atomic_load(&status.presentation_updates),
					paused,
					buffering,
					rebuffers,
					status == nil ? -1 : f64(sync.atomic_load(&status.frame_ns)) / 1e9,
				)
				report_at = wall + 1
			}
			if played >= f64(o.seconds) {break}
			time.sleep(5 * time.Millisecond)
		}
		fmt.printf(
			"{{\"summary\":true,\"decoder_test\":true,\"mode\":\"%s\",\"width\":%d,\"height\":%d,\"fps\":%.3f,\"startup_s\":%.3f,\"played_s\":%.3f,\"max_video_buffer_s\":%.3f,\"max_audio_buffer_s\":%.3f,\"max_rss_kib\":%d,\"decoder_error\":%d,\"reader_error\":%d,\"seek_issued\":%v,\"rebuffers\":%d}}\n",
			o.mode,
			tracks[0].width,
			tracks[0].height,
			tracks[0].fps,
			startup,
			played,
			max_video,
			max_audio,
			diagnostics.peak_rss_kib(),
			status == nil ? 0 : sync.atomic_load(&status.error),
			sync.atomic_load(&s.failure),
			seek_done,
			rebuffers,
		)
		return failure || played < f64(o.seconds) ? 1 : 0
	}
}
