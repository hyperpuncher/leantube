package main

import model "../../src/model"
import reader "../../src/playback"
import sb "../../src/sponsorblock"
import yt "../../src/youtube"
import "core:c"
import queue "core:container/queue"
import "core:encoding/json"
import "core:strings"
import "core:sync"
import "core:testing"
import sdl "vendor:sdl3"

PLAYBACK_BENCH :: #config(PLAYBACK_BENCH, false)

// Only the LG and history-request boundaries are replaced. Decoder queues and player code are real.
Starfish :: struct {}
Decoder_Status :: struct {
	loaded, error, playing, ended, resetting: i32,
	frame_ns:                                 i64,
}
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
fake_full, fake_seek_failure, fake_rate_audio, fake_controls_visible: bool
fake_target_ms: i64
signed_in: bool
account_revision, playback: u32
fake_history_positions: [dynamic]f64

queue_watch_history :: proc(_: string, _: f64, position: f64, _: u32, _: u32, _: bool) -> bool {
	append(&fake_history_positions, position)
	return true
}

sf_video_limits :: proc(_: cstring, _: ^c.int, _: ^c.int, _: ^c.int) -> bool {return false}
display_started :: proc() -> bool {return true}
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
decoder_close :: proc(_: ^Starfish, _: ^Decoder_Status) -> bool {fake_close += 1; return true}
sf_seek :: proc(_: ^Starfish, body: cstring) -> bool {
	position: i64
	if json.unmarshal(transmute([]u8)string(body), &position) != nil {return false}
	fake_target_ms = position
	return !fake_seek_failure
}
decoder_feed :: proc(_: ^Starfish, t: ^reader.Track, limit: f64) -> bool {
	if fake_full {return true}
	for reader.current_packet(t) && queue.front(&t.packets).pts <= limit {
		p := queue.pop_front(&t.packets)
		reader.av_packet_free(&p.packet)
	}
	return true
}
resolved_position: f64
resolved_calls: int
resolve_selected :: proc(position_ms: f64 = 0, _: bool = false) {
	resolved_position = position_ms
	resolved_calls += 1
}

@(test)
opening_a_card_starts_at_its_resume_position :: proc(t: ^testing.T) {
	append(&catalog.videos, model.Video{})
	selected = 0
	defer model.catalog_destroy(&catalog)
	for fixture in ([]struct {
			card:     model.Video,
			expected: f64,
		}{{model.Video{duration_ms = 600000, resume_ms = 123500}, 123500}, {model.Video{duration_ms = 600000}, 0}, {model.Video{duration_ms = 600000, resume_ms = 600000}, 0}, {model.Video{duration_ms = 600000, resume_ms = 700000}, 0}, {model.Video{resume_ms = 123500}, 123500}, {model.Video{resume_ms = -1}, 0}}) {
		catalog.videos[0] = fixture.card
		resolved_position = -1
		start_video()
		testing.expect_value(t, resolved_position, fixture.expected)
	}
	selected = -1
	resolved_position = -1
	start_video()
	testing.expect_value(t, resolved_position, f64(-1))
	selected = 0
}
@(test)
initial_load_keeps_resume_or_explicit_time_and_applies_sponsorblock :: proc(t: ^testing.T) {
	append(&catalog.videos, model.Video{duration_ms = 600000, watched_percent = 35})
	selected = 0
	signed_in = false
	defer model.catalog_destroy(&catalog)
	for fixture in ([]struct {
			position, expected: f64,
			sponsor:            bool,
		}{{210000, 210000, false}, {0, 0, false}, {42000, 42000, false}, {210000, 220000, true}}) {
		if fixture.sponsor {append(&sponsor_segments, sb.Segment{start_ms = 200000, end_ms = 220000, video_duration_ms = 600000})}
		// Empty URLs never contact a server; inspect the real reader's startup options.
		load_video({duration_ms = 600000}, nil, fixture.position, true)
		if testing.expect(t, player_reader != nil) {
			testing.expect_value(t, player_reader.tracks[0].options.start, fixture.expected / 1000)
			testing.expect_value(t, timeline.position_ms, fixture.expected)
			testing.expect(t, paused)
		}
		stop_playback()
	}
}

player_controls_visible :: proc() -> bool {return paused || !loaded || fake_controls_visible}

prepare_player :: proc(end: f64) {
	fake_open, fake_close, fake_pause, fake_eos = 0, 0, 0, 0
	resolved_calls, resolved_position = 0, 0
	player_recoveries, player_recovery_at = 0, 0
	fake_full, fake_seek_failure, fake_rate_audio = false, false, false
	fake_controls_visible = true
	signed_in = false
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
history_reports_presented_positions_and_does_not_record_paused_seeks :: proc(t: ^testing.T) {
	prepare_player(4)
	append(
		&catalog.videos,
		model.Video{id = strings.clone("other")},
		model.Video{id = strings.clone("C5WDBA2i9nE")},
	)
	defer model.catalog_destroy(&catalog)
	signed_in = true
	account_revision = 1
	player_history = {
		id                = strings.clone("C5WDBA2i9nE"),
		account           = 1,
		playback          = 2,
		position          = -1,
		reported_position = -1,
	}
	defer {stop_playback(); signed_in = false; account_revision = 0; delete(fake_history_positions)
		fake_history_positions = nil}
	poll_player()
	testing.expect_value(t, len(fake_history_positions), 0)
	sync.atomic_store(&fake_status.frame_ns, 1_000_000_000)
	poll_player()
	testing.expect_value(t, len(fake_history_positions), 1)
	testing.expect_value(t, fake_history_positions[0], f64(1))
	_ = player_pause(true)
	sync.atomic_store(&fake_status.frame_ns, 2_000_000_000)
	poll_player()
	testing.expect_value(t, len(fake_history_positions), 1)
	_ = player_pause(false)
	sync.atomic_store(&fake_status.frame_ns, 2_500_000_000)
	poll_player()
	testing.expect(
		t,
		len(fake_history_positions) == 1,
		"continuous playback must not queue more reports",
	)
	_ = player_pause(true)
	testing.expect_value(t, len(fake_history_positions), 2)
	testing.expect_value(t, fake_history_positions[1], f64(2.5))
	_ = player_seek(3000)
	stop_playback()
	testing.expect(
		t,
		len(fake_history_positions) == 2,
		"a paused seek must not report an unwatched position",
	)
	testing.expect_value(t, catalog.videos[0].watched_percent, f32(0))
	testing.expect_value(t, catalog.videos[1].watched_percent, f32(25))
	testing.expect_value(t, catalog.videos[1].resume_ms, f64(2500))
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
	fake_controls_visible, dirty = false, false
	sync.atomic_store(&fake_status.frame_ns, 3_100_000_000)
	poll_player(); poll_player()
	testing.expect(t, loaded && dirty, "the first displayed frame must remove the loading UI")
	dirty = false
	sync.atomic_store(&fake_status.frame_ns, 3_150_000_000)
	poll_player()
	testing.expect_value(t, player_clock, f64(3.15))
	testing.expect(t, !dirty, "playback must advance without redrawing hidden controls")
	testing.expect_value(t, fake_eos, 1)
	testing.expect(t, !return_to_grid)
	poll_player()
	testing.expect_value(t, fake_eos, 1)
	sync.atomic_store(&fake_status.ended, 1)
	poll_player()
	testing.expect(t, return_to_grid)
}

@(test)
controls_preserve_pause_audio_and_retarget_the_existing_decoder :: proc(t: ^testing.T) {
	prepare_player(4)
	defer stop_playback()
	poll_player()
	testing.expect(t, player_pause(true) && paused)
	testing.expect_value(t, fake_pause, 1)
	rate = 1.5
	testing.expect(t, player_rate(rate) && fake_rate_audio)
	loaded = true
	testing.expect(t, player_seek(2000))
	testing.expect(t, paused && !loaded)
	for &track in player_reader.tracks {testing.expect_value(t, queue.len(track.packets), 0)}
	testing.expect(t, seek_to(3000) && seek_to(4000))
	testing.expect_value(t, timeline.seek_target_ms, f64(4000))
	testing.expect_value(t, fake_target_ms, i64(4000))
	for &track in player_reader.tracks {
		track.end = 7
		queue.push_back(
			&track.packets,
			{
				packet = reader.av_packet_alloc(),
				pts = 4,
				end = 7,
				generation = sync.atomic_load(&player_reader.state.generation),
			},
		)
	}
	poll_player()
	testing.expect(t, loaded && paused, "a seek must finish without resuming paused playback")
	testing.expect_value(t, fake_open, 1)
	testing.expect_value(t, fake_close, 0)
}

@(test)
seek_sends_plain_milliseconds :: proc(t: ^testing.T) {
	body := seek_message(550283.9)
	defer delete(body)
	testing.expect_value(t, string(body), "550283")
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
failed_seek_does_not_reload_the_decoder :: proc(t: ^testing.T) {
	prepare_player(4)
	defer stop_playback()
	poll_player()
	fake_seek_failure = true
	loaded = true
	testing.expect(t, !player_seek(2000))
	poll_player()
	testing.expect_value(t, fake_open, 1)
	testing.expect_value(t, fake_close, 0)
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

@(test)
reader_failure_re_resolves_at_the_current_position :: proc(t: ^testing.T) {
	prepare_player(60)
	defer stop_playback()
	player_clock = 12
	sync.atomic_store(&player_reader.state.failure, reader.ERROR_IO)
	poll_player()
	testing.expect_value(t, resolved_calls, 1)
	testing.expect_value(t, resolved_position, f64(12000))
	testing.expect(t, player_reader == nil, "recovery must stop the failed session")
}
