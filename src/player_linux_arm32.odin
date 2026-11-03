package main

import "./model"
import reader "./playback"
import sb "./sponsorblock"
import yt "./youtube"
import "core:c"
import "core:fmt"
import "core:math"
import "core:strings"
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
Player_Transition :: struct {
	started_ms, unload_ms, loaded_ms, presentation_ms: u64,
	queue_kept:                                        bool,
}
player_transition: Player_Transition

Player_History :: struct {
	id:                                 string,
	account, playback:                  u32,
	start, position, reported_position: f64,
}
player_history: Player_History

report_player_history :: proc(finished: bool = false) {
	h := &player_history
	if h.id == "" ||
	   h.account != account_revision ||
	   !signed_in ||
	   h.position < 0 ||
	   (h.position == h.reported_position && !finished) {return}
	if duration_ms > 0 {
		for &video in catalog.videos {
			if video.id == h.id {
				video.watched_percent =
					finished ? 100 : f32(clamp(h.position * 1000 / duration_ms * 100, 0, 100))
			}
		}
	}
	if queue_watch_history(h.id, h.start, h.position, h.account, h.playback, finished) {
		h.reported_position, h.start = h.position, h.position
	}
}

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

player_read_end :: proc(position_ms: f64) -> f64 {
	from, _ := sb.next_skip(sponsor_segments[:], position_ms, duration_ms)
	return from >= 0 ? max(from, position_ms) / 1000 : 0
}

load_video :: proc(
	stream: yt.Stream,
	_: ^sdl.Renderer,
	position_ms: f64 = 0,
	start_paused: bool = false,
) {
	assert(player_reader == nil && player_api == nil)
	duration_ms =
		stream.duration_ms > 0 ? stream.duration_ms : catalog.videos[selected].duration_ms
	start := max(position_ms, sb.skip_target(sponsor_segments[:], position_ms, duration_ms))
	if start > position_ms {sb.mark_skipped(sponsor_segments[:], position_ms, start)}
	if duration_ms > 0 && start >= duration_ms {return_to_grid = true; return}
	player_reader = reader.open(
		stream.url,
		stream.audio_url,
		{
			mode = "curl-auto",
			decoder_preroll = true,
			start = start / 1000,
			end = player_read_end(start),
		},
	)
	if player_reader == nil {player_failed(); return}
	player_transition = {
		started_ms = sdl.GetTicks(),
	}
	player_clock = start / 1000
	if signed_in {
		player_history = {
			id                = strings.clone(catalog.videos[selected].id),
			account           = account_revision,
			playback          = playback,
			start             = player_clock,
			position          = -1,
			reported_position = -1,
		}
	}
	player_applied_rate = 1
	player_bound, player_buffering, player_eos = false, false, false
	player_last_play = 0
	player_progress_at = sdl.GetTicks()
	loaded, paused, browsing = false, start_paused, false
	timeline = {
		position_ms    = start,
		seek_target_ms = -1,
	}
	rate = 1
	notice = ""
	dirty = true
}

start_video :: proc() {
	if selected < 0 || selected >= len(catalog.videos) {return}
	resolve_selected()
}

stop_playback :: proc() {
	report_player_history()
	delete(player_history.id)
	player_history = {}
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
	if value {report_player_history()}
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
	if player_reader == nil || return_to_grid {return false}
	report_player_history()
	if duration_ms > 0 &&
	   (target >= duration_ms ||
			   sb.skip_target(sponsor_segments[:], target, duration_ms) >= duration_ms) {
		return_to_grid = true; return true
	}
	player_transition = {
		started_ms = sdl.GetTicks(),
	}
	if player_api != nil && !decoder_close(player_api, player_status) {
		player_api, player_status = nil, nil
		player_failed(); return false
	}
	player_transition.unload_ms = sdl.GetTicks() - player_transition.started_ms
	player_api, player_status = nil, nil
	player_clock = target / 1000
	player_history.start, player_history.position = player_clock, -1
	generation := sync.atomic_load(&player_reader.state.generation)
	reader.seek(player_reader, player_clock, player_read_end(target))
	player_transition.queue_kept = generation == sync.atomic_load(&player_reader.state.generation)
	v, a := &player_reader.tracks[0], &player_reader.tracks[1]
	sync.mutex_lock(&v.mutex); sync.mutex_lock(&a.mutex)
	fmt.printf(
		"player seek target_s=%.3f queue_kept=%v video_s=%.3f audio_s=%.3f\n",
		player_clock,
		generation == sync.atomic_load(&player_reader.state.generation),
		reader.ahead(v, player_clock),
		reader.ahead(a, player_clock),
	)
	sync.mutex_unlock(&a.mutex); sync.mutex_unlock(&v.mutex)
	player_bound, player_buffering, player_eos = false, false, false
	loaded = false
	player_applied_rate = 1
	player_progress_at = sdl.GetTicks()
	return true
}

finish_sponsor_span :: proc() {
	// Read the original millisecond boundary, without a seconds round trip.
	from, _ := sb.next_skip(
		sponsor_segments[:],
		player_reader.state.skip_start * 1000,
		duration_ms,
	)
	if from >= 0 {skip_sponsor_at(from, player_clock * 1000)}
}

poll_player :: proc() {
	if player_reader == nil || return_to_grid {return}
	s := player_reader
	if sync.atomic_load(&s.state.failure) != 0 {player_failed("reader"); return}
	if s.state.skip_end == 0 {
		from, to := sb.next_skip(sponsor_segments[:], player_clock * 1000, duration_ms)
		if from >= 0 && to < duration_ms {
			_ = reader.prepare_skip(s, from / 1000, to / 1000, player_read_end(to))
		}
	}
	v, a := &s.tracks[0], &s.tracks[1]
	sync.mutex_lock(&v.mutex); sync.mutex_lock(&a.mutex)
	vb, ab := reader.ahead(v, player_clock), reader.ahead(a, player_clock)
	ready :=
		(vb >= reader.STARTUP_SECONDS || v.eof) &&
		(ab >= reader.STARTUP_SECONDS || a.eof) &&
		reader.current_packet(v) &&
		reader.current_packet(a)
	starved := (!reader.span_closed(v) && vb < 0.05) || (!reader.span_closed(a) && ab < 0.05)
	no_tail := v.eof && a.eof && (!reader.current_packet(v) || !reader.current_packet(a))
	missing_head := !reader.current_packet(v) || !reader.current_packet(a)
	buffer_end := min(v.end, a.end) * 1000
	sync.mutex_unlock(&a.mutex); sync.mutex_unlock(&v.mutex)
	if model.set_buffered_range(&timeline, player_clock * 1000, buffer_end, duration_ms) &&
	   player_controls_visible() {dirty = true}
	if player_api == nil &&
	   s.state.skip_end > 0 &&
	   (missing_head || player_clock >= s.state.skip_start) {
		if !paused {finish_sponsor_span()}
		return
	}
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
		player_transition.loaded_ms = sdl.GetTicks() - player_transition.started_ms
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
		if player_transition.presentation_ms == 0 {
			player_transition.presentation_ms = now - player_transition.started_ms
		}
		next := max(player_clock, f64(frame) / 1e9)
		if next != player_clock || !loaded {
			if player_controls_visible() {dirty = true}
			if next != player_clock {
				player_progress_at = now
				if !paused && !player_buffering {
					player_history.position = next
					if player_history.reported_position < 0 {report_player_history()}
				}
			}
			player_clock = next
			timeline.position_ms = next * 1000
			if timeline.seek_target_ms >= 0 {model.seek_done(&timeline)}
			loaded = !player_buffering
		}
		sync.atomic_store(&s.state.position, player_clock)
		for &t in s.tracks {sync.mutex_lock(&t.mutex); sync.cond_signal(&t.changed); sync.mutex_unlock(&t.mutex)}
	}
	if !paused && s.state.skip_end > 0 && player_clock >= s.state.skip_start {
		finish_sponsor_span()
		return
	}
	sync.mutex_lock(&v.mutex); sync.mutex_lock(&a.mutex)
	drained := reader.span_drained(v) && reader.span_drained(a)
	sync.mutex_unlock(&a.mutex); sync.mutex_unlock(&v.mutex)
	if drained && !player_eos {
		if !sf_eos(player_api) {player_failed(); return}
		player_eos = true
	}
	if sync.atomic_load(&status.ended) != 0 {
		if s.state.skip_end > 0 {
			if !paused {finish_sponsor_span()}
		} else {report_player_history(true); return_to_grid = true}
		return
	}
	if paused {player_progress_at = now}
	if now - player_progress_at > 45000 {player_failed()}
}
