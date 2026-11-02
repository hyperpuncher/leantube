package main

import reader "./playback"
import queue "core:container/queue"
import "core:encoding/json"
import "core:os"
import "core:sync"
import "core:sys/posix"
import sdl "vendor:sdl3"

CONTROL_STATE :: "/tmp/leantube-state.json"
control_saved_at: u64

Track_State :: struct {
	ahead_s:                        f64,
	ranges_s:                       [][2]f64,
	packets:                        int,
	end_of_input, sponsor_boundary: bool,
	codec:                          string,
	width, height, transfer:        int,
	fps:                            f64,
}

track_state :: proc(track: ^reader.Track, ranges: [][2]f64) -> Track_State {
	state := Track_State {
		ranges_s = ranges[:0],
	}
	// The queue contains at most the current span and one prepared span.
	previous: u32
	for index in 0 ..< queue.len(track.packets) {
		p := queue.get(&track.packets, index)
		if index == 0 || p.generation != previous {
			assert(len(state.ranges_s) < len(ranges))
			count := len(state.ranges_s)
			state.ranges_s = ranges[:count + 1]
			state.ranges_s[count] = {p.pts, p.end}
		} else {
			last := &state.ranges_s[len(state.ranges_s) - 1]
			last[0], last[1] = min(last[0], p.pts), max(last[1], p.end)
		}
		previous = p.generation
	}
	state.ahead_s = reader.ahead(track, player_clock)
	state.packets = queue.len(track.packets)
	state.end_of_input, state.sponsor_boundary = track.eof, track.at_limit
	state.codec, state.fps = track.codec, track.fps
	state.width, state.height = int(track.width), int(track.height)
	state.transfer = int(track.color_transfer)
	return state
}

write_control_state :: proc(stopped: bool = false) {
	now := sdl.GetTicks()
	if !stopped && now - control_saved_at < 200 && control_saved_at >= control_started_at {return}
	control_saved_at = now
	state := struct {
		pid:                                                     int,
		version:                                                 string,
		command_elapsed_ms:                                      u64,
		phase, error, video_id:                                  string,
		position_ms, native_position_ms, target_ms, duration_ms: f64,
		paused:                                                  bool,
		video, audio:                                            Track_State,
		last_transition:                                         Player_Transition,
		frames_presented, frames_dropped:                        i64,
	} {
		pid                = int(posix.getpid()),
		version            = APP_VERSION,
		command_elapsed_ms = now - control_started_at,
		phase              = "idle",
		error              = control_error,
		position_ms        = timeline.position_ms,
		native_position_ms = -1,
		target_ms          = timeline.seek_target_ms,
		duration_ms        = duration_ms,
		paused             = paused,
		last_transition    = player_transition,
	}
	if selected >= 0 &&
	   selected < len(catalog.videos) {state.video_id = catalog.videos[selected].id}
	video_ranges, audio_ranges: [2][2]f64
	if resolving {state.phase = "resolving"}
	if s := player_reader; s != nil {
		sync.mutex_lock(&s.tracks[0].mutex); sync.mutex_lock(&s.tracks[1].mutex)
		state.video = track_state(&s.tracks[0], video_ranges[:])
		state.audio = track_state(&s.tracks[1], audio_ranges[:])
		sync.mutex_unlock(&s.tracks[1].mutex); sync.mutex_unlock(&s.tracks[0].mutex)
		state.phase = "buffering"
		if player_status != nil {
			frame := sync.atomic_load(&player_status.frame_ns)
			if frame >= 0 {state.native_position_ms = f64(frame) / 1e6}
			state.frames_presented = sync.atomic_load(&player_status.presentation_updates)
			state.frames_dropped = sync.atomic_load(&player_status.dropped)
			switch {
			case sync.atomic_load(&player_status.loaded) == 0:
				state.phase = "decoder-load"
			case player_buffering:
				state.phase = "buffering"
			case !loaded:
				state.phase = "preroll"
			case paused:
				state.phase = "paused"
			case:
				state.phase = "playing"
			}
		}
	}
	if notice != "" {state.phase, state.error = "error", notice}
	if stopped {state.phase = "stopped"}
	bytes, err := json.marshal(state)
	if err != nil {return}
	defer delete(bytes)
	// Atomic replacement keeps readers from seeing partial JSON.
	if os.write_entire_file(CONTROL_STATE + ".new", bytes, {.Read_User, .Write_User}) == nil {
		_ = os.rename(CONTROL_STATE + ".new", CONTROL_STATE)
	}
}
