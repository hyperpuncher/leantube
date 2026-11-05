package main

import "core:math"

Starfish_Load_Config :: struct {
	app_id, video_codec:                 string,
	width, height, fps_value, fps_scale: i32,
	fps, target_seconds:                 f64,
	audio_rate, audio_channels:          int,
	window_id:                           string,
}

// Only the load fields used by LeanTube. Native names and zero values matter.
Starfish_Load_Request :: struct {
	args: [1]struct {
		mediaTransportType: string,
		option:             struct {
			appId:                 string,
			windowId:              string `json:"windowId,omitempty"`,
			queryPosition:         bool,
			seekMode:              string,
			transmission:          struct {
				trickType: string,
			},
			externalStreamingInfo: struct {
				contents:         struct {
					format, provider: string,
					codec:            struct {
						video, audio: string,
					},
					esInfo:           struct {
						pauseAtDecodeTime, seperatedPTS:                       bool,
						ptsToDecode:                                           i64, // nanoseconds; Seek.position uses milliseconds.
						videoWidth, videoHeight, videoFpsValue, videoFpsScale: i32,
					},
					aacInfo:          struct {
						channels:  int,
						format:    string,
						frequency: f64, // kHz, not Hz.
						profile:   int,
					},
				},
				restartStreaming: bool,
				totalStreamSize:  int, // inherited value; unit not verified.
				bufferingCtrInfo: struct {
					preBufferByte, bufferMinLevel, bufferMaxLevel: int,
					qBufferLevelAudio, qBufferLevelVideo:          int,
					srcBufferLevelAudio:                           struct {
						minimum, maximum: int,
					},
					srcBufferLevelVideo:                           struct {
						minimum, maximum: int,
					},
				},
			},
			adaptiveStreaming:     struct {
				audioOnly:           bool,
				maxWidth, maxHeight: i32,
				maxFrameRate:        f64,
			},
		},
	},
}

starfish_load_request :: proc(config: Starfish_Load_Config) -> Starfish_Load_Request {
	return {
		args = {
			{
				mediaTransportType = "BUFFERSTREAM",
				option = {
					appId = config.app_id,
					windowId = config.window_id,
					queryPosition = false,
					// Explicit seeks must keep the selected playback rate.
					seekMode = "keep-rate",
					// Rate changes must not seek or flush the supplied packets.
					transmission = {trickType = "client-side"},
					externalStreamingInfo = {
						contents = {
							format = "RAW",
							provider = "Chrome",
							codec = {video = config.video_codec, audio = "AAC"},
							esInfo = {
								pauseAtDecodeTime = false,
								seperatedPTS = true,
								ptsToDecode = i64(config.target_seconds * 1e9),
								videoWidth = config.width,
								videoHeight = config.height,
								videoFpsValue = config.fps_value,
								videoFpsScale = config.fps_scale,
							},
							aacInfo = {
								channels = config.audio_channels,
								format = "adts",
								frequency = f64(config.audio_rate) / 1000,
								profile = 2,
							},
						},
						restartStreaming = false,
						totalStreamSize = 256,
						bufferingCtrInfo = {
							preBufferByte = 0,
							bufferMinLevel = 0,
							bufferMaxLevel = 0,
							qBufferLevelAudio = 0,
							qBufferLevelVideo = 0,
							srcBufferLevelAudio = {minimum = 1024, maximum = 1048576},
							srcBufferLevelVideo = {minimum = 1024, maximum = 8388608},
						},
					},
					adaptiveStreaming = {
						audioOnly    = false,
						maxWidth     = config.width,
						maxHeight    = config.height,
						// Preserve the previous request's six-decimal frame-rate value.
						maxFrameRate = math.round(config.fps * 1e6) / 1e6,
					},
				},
			},
		},
	}
}
