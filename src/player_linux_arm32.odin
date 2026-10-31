package main

import "./model"
import reader "./playback"
import yt "./youtube"
import "core:c"
import queue "core:container/queue"
import "core:fmt"
import "core:math"
import "core:sync"
import sdl "vendor:sdl3"

native_video_codec :: proc(codec: string) -> cstring {
	switch codec {
	case "h264":
		return "H264"
	case "hevc":
		return "H265"
	case "vp9":
		return "VP9"
	case "av1":
		return "AV1"
	}
	return nil
}

init_player :: proc() {
	for codec, i in ([]string{"h264", "hevc", "vp9", "av1"}) {
		width, height, fps: c.int
		ok := sf_video_limits(native_video_codec(codec), &width, &height, &fps)
		playback_limits[i] = {
			codec = codec,
		}
		if ok {playback_limits[i] = {codec, int(width), int(height), int(fps)}}
		fmt.printf(
			"native codec=%s available=%v width=%d height=%d fps=%d\n",
			codec,
			ok,
			width,
			height,
			fps,
		)
	}
}

player_reader: ^reader.Session
player_api: ^Starfish
player_status: ^Decoder_Status
player_bound, player_buffering, player_eos: bool
player_clock, player_applied_rate: f64
player_last_play, player_progress_at: u64
when PLAYBACK_BENCH {player_report_at: u64}

player_failed :: proc(stage: string = "native") {
	fmt.eprintf(
		"player failure stage=%s reader=%d native=%d\n",
		stage,
		player_reader == nil ? 0 : sync.atomic_load(&player_reader.state.failure),
		player_status == nil ? 0 : sync.atomic_load(&player_status.error),
	)
	notice = "video playback failed; choose another video"
	return_to_grid = true
	dirty = true
}

load_video :: proc(stream: yt.Stream, _: ^sdl.Renderer) {
	assert(player_reader == nil && player_api == nil)
	player_reader = reader.open(
		stream.url,
		stream.audio_url,
		{mode = "curl-h3", decoder_preroll = true},
	)
	if player_reader == nil {player_failed(); return}
	player_clock = 0
	player_applied_rate = 1
	player_bound, player_buffering, player_eos = false, false, false
	player_last_play = 0
	player_progress_at = sdl.GetTicks()
	loaded, paused, browsing = false, false, false
	timeline = {
		seek_target_ms = -1,
	}
	rate = 1
	duration_ms = catalog.videos[selected].duration_ms
	notice = ""
	dirty = true
}

start_video :: proc() {
	if selected < 0 || selected >= len(catalog.videos) {return}
	resolve_selected()
}

stop_playback :: proc() {
	// Stop network input before unloading the decoder. Callback storage stays
	// live until native unload completion, including on load failure.
	if player_reader != nil {reader.stop(player_reader)}
	if player_api != nil {_ = decoder_close(player_api, player_status)}
	player_api, player_status = nil, nil
	reader.close(player_reader); player_reader = nil
	loaded, paused, resolving = false, false, false
	delete(sponsor_segments); sponsor_segments = nil
	timeline = {
		seek_target_ms = -1,
	}
	browsing, return_to_grid, dirty, library_focus_pending = true, false, true, true
}

player_pause :: proc(value: bool) -> bool {
	if player_reader == nil {return false}
	if player_api != nil && value && !sf_pause(player_api) {return false}
	paused = value
	player_progress_at = sdl.GetTicks()
	return true
}

player_rate :: proc(value: f64) -> bool {
	if player_api == nil ||
	   math.is_nan(value) ||
	   math.is_inf(value) ||
	   value < 0.5 ||
	   value > 2 {return false}
	body := fmt.caprintf(`{{"playRate":%.6f,"audioOutput":true}}`, value)
	defer delete(body)
	if !sf_rate(player_api, body) {return false}
	player_applied_rate = value
	fmt.printf("player requested_rate=%.2f position_s=%.3f\n", value, player_clock)
	return true
}

player_seek :: proc(target: f64) -> bool {
	if math.is_nan(target) || math.is_inf(target) || target < 0 {return false}
	if player_reader == nil || (!loaded && player_api == nil) {return false}
	if duration_ms > 0 && target >= duration_ms {return_to_grid = true; return true}
	if player_api != nil && !decoder_close(player_api, player_status) {
		player_api, player_status = nil, nil
		player_failed(); return false
	}
	player_api, player_status = nil, nil
	player_clock = target / 1000
	reader.seek(player_reader, player_clock)
	player_bound, player_buffering, player_eos = false, false, false
	loaded = false
	player_applied_rate = 1
	player_progress_at = sdl.GetTicks()
	return true
}

poll_player :: proc() {
	if player_reader == nil || return_to_grid {return}
	s := player_reader
	if sync.atomic_load(&s.state.failure) != 0 {player_failed("reader"); return}
	v, a := &s.tracks[0], &s.tracks[1]
	sync.mutex_lock(&v.mutex); sync.mutex_lock(&a.mutex)
	vb, ab := reader.ahead(v, player_clock), reader.ahead(a, player_clock)
	ready :=
		(vb >= reader.STARTUP_SECONDS || v.eof) &&
		(ab >= reader.STARTUP_SECONDS || a.eof) &&
		queue.len(v.packets) > 0 &&
		queue.len(a.packets) > 0
	starved := (!v.eof && vb < 0.05) || (!a.eof && ab < 0.05)
	no_tail := v.eof && a.eof && (queue.len(v.packets) == 0 || queue.len(a.packets) == 0)
	sync.mutex_unlock(&a.mutex); sync.mutex_unlock(&v.mutex)
	if player_api == nil && no_tail {
		if player_clock > 0 {return_to_grid = true} else {player_failed()}
		return
	}
	if player_api == nil && ready {
		player_api, player_status = decoder_open(v, a, player_clock)
		if player_api == nil {player_failed(); return}
		player_last_play = 0
		stream_width, stream_height = int(v.width), int(v.height)
	}
	if player_api == nil {
		if sdl.GetTicks() - player_progress_at > 45000 {player_failed()}
		return
	}
	status := player_status
	if sync.atomic_load(&status.error) != 0 {player_failed("decoder"); return}
	if sync.atomic_load(&status.loaded) != 0 && !player_bound {
		task: c.long
		sink := AcbAPI_setSinkType(acb_id, 0)
		state := AcbAPI_setState(acb_id, .Foreground, .Loaded, &task)
		fmt.eprintf("player display sink=%v state=%d\n", sink, state)
		// The main sink request can return false when the default sink is
		// already in use. The loaded state is the required transition.
		if state < 0 {player_failed("display"); return}
		player_bound = true
	}
	frame := sync.atomic_load(&status.frame_ns)
	if !player_buffering && !paused && frame >= 0 && starved {
		if !sf_pause(player_api) {player_failed(); return}
		player_buffering = true
		loaded = false
		dirty = true
	}
	if player_buffering && ready {player_buffering = false; dirty = true}
	// Feed initial pre-roll while paused too, without an unsolicited Play.
	if !player_buffering {
		if !decoder_feed(player_api, a, player_clock + 1) ||
		   !decoder_feed(player_api, v, player_clock + 1) {player_failed("feed"); return}
	}
	if player_bound &&
	   rate != player_applied_rate &&
	   !player_rate(rate) {player_failed("rate"); return}
	now := sdl.GetTicks()
	if !paused &&
	   !player_buffering &&
	   now - player_last_play >= 250 &&
	   sync.atomic_load(&status.playing) == 0 {
		_ = sf_play(player_api)
		player_last_play = now
	}
	if paused && player_bound && !player_buffering && !loaded {
		// Paused native pipelines can display pre-roll without timestamp
		// callbacks. Load completion must also finish the paused seek UI.
		loaded = true
		model.seek_done(&timeline)
		dirty = true
	}
	when PLAYBACK_BENCH {
		if now - player_report_at >= 1000 {
			fmt.printf(
				"player position_s=%.3f native_s=%.3f requested_rate=%.2f paused=%v buffering=%v video_s=%.3f audio_s=%.3f playing=%d\n",
				player_clock,
				f64(frame) / 1e9,
				rate,
				paused,
				player_buffering,
				vb,
				ab,
				sync.atomic_load(&status.playing),
			)
			player_report_at = now
		}
	}
	if frame >= 0 {
		next := max(player_clock, f64(frame) / 1e9)
		if next != player_clock || !loaded {
			if next != player_clock {player_progress_at = now}
			player_clock = next
			timeline.position_ms = next * 1000
			if timeline.seek_target_ms >= 0 {model.seek_done(&timeline)}
			loaded = !player_buffering
			dirty = true
		}
		sync.atomic_store(&s.state.position, player_clock)
		for &t in s.tracks {sync.mutex_lock(&t.mutex); sync.cond_signal(&t.changed); sync.mutex_unlock(&t.mutex)}
	}
	sync.mutex_lock(&v.mutex); sync.mutex_lock(&a.mutex)
	drained := v.eof && a.eof && queue.len(v.packets) == 0 && queue.len(a.packets) == 0
	sync.mutex_unlock(&a.mutex); sync.mutex_unlock(&v.mutex)
	if drained && !player_eos {
		if !sf_eos(player_api) {player_failed(); return}
		player_eos = true
	}
	if sync.atomic_load(&status.ended) != 0 {return_to_grid = true}
	if paused {player_progress_at = now}
	if now - player_progress_at > 45000 {player_failed()}
}
