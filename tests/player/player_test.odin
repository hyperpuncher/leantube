package main

import model "../../src/model"
import reader "../../src/playback"
import sb "../../src/sponsorblock"
import yt "../../src/youtube"
import "core:c"
import queue "core:container/queue"
import "core:strings"
import "core:sync"
import "core:testing"
import sdl "vendor:sdl3"

PLAYBACK_BENCH :: #config(PLAYBACK_BENCH, false)

// Only the external LG boundary is replaced. Queues and player code are real.
Starfish :: struct {}
Decoder_Status :: struct {
	loaded, error, playing, ended: i32,
	frame_ns:                      i64,
}
App_State :: enum {
	Foreground,
}
Play_State :: enum {
	Loaded,
}
acb_id: c.long
playback_limits: [4]yt.Video_Limit
running, paused, loaded, browsing, resolving, return_to_grid, dirty, library_focus_pending: bool
notice: string
stream_width, stream_height, selected: int
rate, duration_ms: f64
timeline: model.Timeline
catalog: model.Catalog
sponsor_segments: [dynamic]sb.Segment
fake_api: Starfish
fake_status: Decoder_Status
fake_open, fake_close, fake_pause, fake_eos: int
fake_full, fake_close_failure, fake_rate_audio: bool

sf_video_limits :: proc(_: cstring, _: ^c.int, _: ^c.int, _: ^c.int) -> bool {return false}
AcbAPI_setSinkType :: proc(_: c.long, _: c.int) -> bool {return false}
AcbAPI_setState :: proc(_: c.long, _: App_State, _: Play_State, _: ^c.long) -> c.int {return 0}
sf_play :: proc(_: ^Starfish) -> bool {sync.atomic_store(&fake_status.playing, 1); return true}
sf_pause :: proc(_: ^Starfish) -> bool {fake_pause += 1; sync.atomic_store(&fake_status.playing, 0)
	return true}
sf_eos :: proc(_: ^Starfish) -> bool {fake_eos += 1; return true}
sf_rate :: proc(_: ^Starfish, body: cstring) -> bool {
	fake_rate_audio = strings.contains(string(body), `"audioOutput":true`)
	return true
}
decoder_open :: proc(_: ^reader.Track, _: ^reader.Track, _: f64) -> (^Starfish, ^Decoder_Status) {
	fake_open += 1
	fake_status = {
		loaded   = 1,
		frame_ns = -1,
	}
	return &fake_api, &fake_status
}
decoder_close :: proc(_: ^Starfish, _: ^Decoder_Status) -> bool {fake_close += 1; return(
		!fake_close_failure \
	)}
decoder_feed :: proc(_: ^Starfish, t: ^reader.Track, limit: f64) -> bool {
	if fake_full {return true}
	for reader.current_packet(t) && queue.front(&t.packets).pts <= limit {
		p := queue.pop_front(&t.packets)
		reader.av_packet_free(&p.packet)
	}
	return true
}
resolve_selected :: proc() {}
player_controls_visible :: proc() -> bool {return true}

prepare_player :: proc(end: f64) {
	fake_open, fake_close, fake_pause, fake_eos = 0, 0, 0, 0
	fake_full, fake_close_failure, fake_rate_audio = false, false, false
	player_api, player_status = nil, nil
	player_reader = new(reader.Session)
	for &t in player_reader.tracks {
		t.state = &player_reader.state
		t.end, t.eof = end, true
		queue.init(&t.packets)
		for pts in ([]f64{0, end - 0.1}) {
			queue.push_back(
				&t.packets,
				{packet = reader.av_packet_alloc(), pts = pts, decode_time = pts, end = pts + 0.1},
			)
		}
	}
	player_clock, player_applied_rate, rate = 0, 1, 1
	player_buffering, player_bound, player_eos = false, false, false
	player_progress_at = sdl.GetTicks()
	paused, loaded, browsing, return_to_grid, running = false, false, false, false, true
	timeline = {
		seek_target_ms = -1,
	}
	duration_ms = 10000
}

@(test)
startup_waits_for_three_seconds_and_eos_waits_for_native_completion :: proc(t: ^testing.T) {
	prepare_player(2.9)
	defer stop_playback()
	for &track in player_reader.tracks {track.eof = false}
	poll_player()
	testing.expect_value(t, fake_open, 0)
	for &track in player_reader.tracks {track.end = 3.2; track.eof = true}
	poll_player()
	testing.expect_value(t, fake_open, 1)
	testing.expect_value(t, fake_eos, 0)
	sync.atomic_store(&fake_status.frame_ns, 3_100_000_000)
	poll_player(); poll_player()
	testing.expect_value(t, fake_eos, 1)
	testing.expect(t, !return_to_grid)
	poll_player()
	testing.expect_value(t, fake_eos, 1)
	sync.atomic_store(&fake_status.ended, 1)
	poll_player()
	testing.expect(t, return_to_grid)
}

@(test)
controls_preserve_pause_audio_rate_and_seek_generation :: proc(t: ^testing.T) {
	prepare_player(4)
	defer stop_playback()
	poll_player()
	testing.expect(t, player_pause(true) && paused)
	testing.expect_value(t, fake_pause, 1)
	testing.expect(t, player_rate(1.5) && fake_rate_audio)
	loaded = true
	testing.expect(t, player_seek(2000))
	testing.expect(t, paused && !loaded && player_api == nil)
	testing.expect_value(t, fake_close, 1)
	testing.expect_value(t, sync.atomic_load(&player_reader.state.generation), u32(1))
	testing.expect_value(t, sync.atomic_load(&player_reader.state.seek_target), f64(2))
	for &track in player_reader.tracks {testing.expect_value(t, queue.len(track.packets), 0)}
	testing.expect(t, seek_to(3000) && seek_to(4000))
	testing.expect_value(t, timeline.seek_target_ms, f64(4000))
}

@(test)
seek_to_end_and_exhausted_seek_tail_do_not_wait_for_packets :: proc(t: ^testing.T) {
	prepare_player(4)
	defer stop_playback()
	poll_player()
	testing.expect(t, player_seek(duration_ms))
	testing.expect(t, return_to_grid)
	return_to_grid = false
	loaded = true
	testing.expect(t, player_seek(9000))
	for &track in player_reader.tracks {track.eof = true}
	poll_player()
	testing.expect(t, return_to_grid)
}

@(test)
failed_unload_prevents_a_second_decoder :: proc(t: ^testing.T) {
	prepare_player(4)
	defer stop_playback()
	poll_player()
	fake_close_failure = true
	loaded = true
	testing.expect(t, !player_seek(2000))
	poll_player()
	testing.expect_value(t, fake_open, 1)
	testing.expect(t, return_to_grid)
}

@(test)
rebuffer_requires_three_seconds_before_resuming :: proc(t: ^testing.T) {
	prepare_player(4)
	defer stop_playback()
	poll_player()
	sync.atomic_store(&fake_status.frame_ns, 2_000_000_000)
	poll_player()
	for &track in player_reader.tracks {reader.clear_track(&track); track.end = 2}
	poll_player()
	testing.expect(t, player_buffering && !loaded)
	testing.expect_value(t, fake_pause, 1)
	fake_full = true
	for &track in player_reader.tracks {
		track.end = 4.9
		queue.push_back(&track.packets, {packet = reader.av_packet_alloc(), pts = 2, end = 4.9})
	}
	poll_player()
	testing.expect(t, player_buffering && !loaded)
	for &track in player_reader.tracks {track.end = 5}
	poll_player()
	testing.expect(t, !player_buffering && loaded && !paused)
}

@(test)
paused_load_completes_ui_without_a_timestamp_callback :: proc(t: ^testing.T) {
	prepare_player(4)
	defer stop_playback()
	paused = true
	timeline.seek_target_ms = 2000
	poll_player()
	testing.expect(t, loaded && paused && player_bound)
	testing.expect_value(t, fake_status.frame_ns, i64(-1))
	testing.expect_value(t, timeline.seek_target_ms, f64(-1))
	testing.expect_value(t, timeline.position_ms, f64(2000))
}

@(test)
buffered_range_uses_the_shorter_track_and_updates_while_paused :: proc(t: ^testing.T) {
	prepare_player(4)
	defer stop_playback()
	paused = true
	player_reader.tracks[0].end = 8
	player_reader.tracks[1].end = 3
	poll_player()
	testing.expect_value(t, timeline.buffer_start_ms, f64(0))
	testing.expect_value(t, timeline.buffer_end_ms, f64(3000))
	player_reader.tracks[1].end = 7
	dirty = false
	poll_player()
	testing.expect_value(t, timeline.buffer_end_ms, f64(7000))
	testing.expect(t, dirty)
	stop_playback()
	testing.expect(t, timeline.buffer_start_ms == 0 && timeline.buffer_end_ms == 0)
}
