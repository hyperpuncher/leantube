# playback diagnostics

the packet reader and raw transport tests measure network delivery and packet queues. they do not decode video or play audio. a successful test does not prove displayed playback, audio synchronization, or HDR output.

## code structure

shared packet reading, HTTP range requests, AAC framing, and session ownership are in the application `playback` package. the command-line tests are in the separate `diagnostics` package. the native decoder interface and decoder test entry are separate Odin files.

a session owns both source URLs, both workers, and both packet queues. both paced and decoder tests use the same open, seek, stop, and close operations. stopping joins the workers before storage is released. opening a session checks the FFmpeg library versions and installs the URL-safe log callback before workers start.

`just bench-reference fetch PLAYER.json START_SECONDS DURATION_SECONDS OUTPUT.yuv ITAG` fetches reference frames from the selected format. the final format ID is optional; without it, the helper uses an available 4K VP9 format. `just bench-reference match OUTPUT.yuv START_SECONDS PICTURE.png` reports the closest source frame. use elapsed time between captures to measure visible speed.

supported transport controls are `ffmpeg`, `curl-reuse` (HTTP/1.1), and `curl-h3` (HTTP/3 only). the old request-size, parallel-range, URL-query-range, aligned-range, and fresh-connection variants have been removed. private historical results are retained.

## prepare

use the patched toolchain from `just setup`. then run:

```sh
just setup-reader
just bench-install
```

the benchmark app uses the LeanTube app ID. neither installed YouTube app is changed. explicit test entry points require a benchmark build. the normal app now uses the same reader and decoder through managed app startup.

keep player responses and results private on the host. the harness sends signed URLs to the TV through SSH input. it does not write media or request files to TV storage. use a new output path for each test. refresh expired player responses.

## paced packet reader

```sh
just bench-reader PLAYER.json RESULT.jsonl curl-h3 180 0 45 120
```

this example consumes 180 seconds of media. after 45 seconds of consumption, it seeks to 120 seconds in the same session. `ffmpeg` is the baseline HTTP transport. `curl-h3` is an HTTP/3-only diagnostic transport. both use FFmpeg to read media packets.

the startup and rebuffer threshold is 3 seconds. each track has a maximum packet queue of 20 seconds. the curl reader also has a response body buffer of up to 1 MiB per track. these limits are not a total memory limit.

## LG decoder test

```sh
LEANTUBE_READER_RCVBUF=524288 just bench-decoder PLAYER.json RESULT.jsonl curl-h3 90 0 20 120
```

this optional test uses the shared Odin reader and bounded packet queues. FFmpeg adds ADTS framing to the original AAC access units; it does not re-encode them. the small upstream C interface calls the installed LG decoder library. the player, packet ownership, clocks, control, and seek handling are Odin code.

the test opens its own native Wayland window. it runs explicitly through SSH, not through the normal app launcher. Back or SIGTERM closes it. Space and the media Play/Pause keys control pause. a seek keeps the FFmpeg inputs open, clears both packet queues, retains video keyframe pre-roll, and recreates the native decoder session. native unload completion is required before another decoder session starts.

startup and rebuffering use the same 3-second threshold. packet queues keep the 20-second limit. the native pipeline also has app-source limits of 8 MiB for video and 1 MiB for audio. decoder buffers and GPU memory are additional. peak RSS is not the total playback memory use.

`presentation_updates` counts native timestamp reports, not displayed frames. some firmware reports these only about five times per second. verify visible pictures separately and compare their content with source frames before claiming a playback speed. a decoder counter alone is not display proof. check audible audio too.

the normal app now selects direct sources using the installed decoder capability limits and uses this reader and decoder. first managed-app TV tests have displayed 4K SDR and 4K60 PQ HDR at 1×. buffer-stream loads now use client-side trick play to avoid flushing app-fed packets on rate changes. the original build stalled at 1080p29.97; captured-frame comparisons with the fix measured about 0.50×, 0.99×, and 1.97× at requested speeds of 0.5×, 1×, and 2×. pause, resume, and seeks also passed. a 4K60 run at 2× measured below target, so higher decoder loads need separate checks. audio synchronization still needs a listening check. source and license details for the C interface are in the vendored Starfish documentation.

## raw transport

```sh
just bench-transport PLAYER.json RESULT.jsonl curl-h3 128 0
```

this example reads 128 MiB from byte offset zero, in sequential 1 MiB ranges. it does not use FFmpeg, audio, or playback pacing. supported transports are `curl-reuse` and `curl-h3`.

use `bench-reader-host` or `bench-transport-host` for the host controls. these commands do not access the TV.

## per-socket receive buffer experiment

```sh
LEANTUBE_READER_RCVBUF=524288 just bench-transport PLAYER.json RESULT.jsonl curl-h3 128 0
LEANTUBE_READER_RCVBUF=524288 just bench-reader PLAYER.json RESULT.jsonl curl-h3 180 0 45 120
```

this variable is only for the curl diagnostics. zero, or an unset variable, leaves the OS default unchanged. positive values request that many bytes with `SO_RCVBUF` on each new connection. accepted requests are from 1 byte to 8 MiB. the OS can limit a request.

the transfer records include `socket_rcvbuf_requested` and `socket_rcvbuf_actual`. the actual value is the kernel value read after the request, before connection setup. curl does not change this option later. Linux can report a larger value that includes packet memory overhead. this is a per-socket limit, not a payload allocation or a process RSS measurement. cached redirect connections can keep more than one socket open.

the experiment does not change TV-wide network settings. it does not increase the packet queue limits or select a lower video quality. compare socket drop counters as well as transfer speed. CDN redirects can change the serving endpoint between tests.

## finish

```sh
just install
just stop
```

verify that no LeanTube process or media pipeline remains. restore the normal app after all TV diagnostics. confirm that nobody is using the TV before a test. concurrent playback makes timing comparisons uncontrolled.

between tests, the existing TV API `luna://com.webos.service.tvpower/power/turnOnScreenSaver` with `{}` can start the built-in screensaver. `power/turnOnScreen` dismisses it without arrow-key input. verify the reported state after each request. an accepted request can still return to `Active`, for example over an HDMI input. in that case, `power/turnOffScreen` can protect the panel without standby; verify `Screen Off`, then use `power/turnOnScreen` before the next measured run. do not change the screensaver configuration or enter standby. keep the power state the same for all measured runs. do not claim a playback fix until displayed frames, audio, pause, seeks, and HDR have been tested.
