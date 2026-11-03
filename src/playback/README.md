# playback reader

this Odin package reads encoded video and audio packets. FFmpeg reads the media containers. curl supplies bounded HTTP byte ranges. with decoder pre-roll enabled, FFmpeg adds ADTS framing to AAC packets and native framing to H.264, HEVC, and AV1 packets. raw video muxers use upstream bitstream filters to add the required headers. it does not re-encode audio or video.

## session ownership

- initialize curl before opening a session. keep curl initialized until all sessions are closed.
- `open` copies both source URLs and starts one worker for each track. it returns a session pointer or `nil` on setup failure.
- do not copy a session. its workers keep pointers to its state and tracks.
- use `seek` from the consumer thread without holding either track mutex. it clears both queues and changes the cancellation generation. workers seek their existing FFmpeg inputs.
- `stop` cancels requests, wakes workers, and joins them. it keeps queues and statistics available for inspection. it can be called more than once.
- `close` stops the workers, frees queued packets and URLs, and frees the session. do not use the pointer after this call.

lock a track mutex before reading or changing its queue or metadata while workers run. when both locks are needed, lock video first, then audio. use atomic operations for shared session state. after changing the playback position, signal each track condition so a worker can continue.

## limits

the reader requires FFmpeg library majors 63, 63, and 61. opening a session checks these versions before workers use the bound C structure prefixes. it also sets a log callback that rejects URL-bearing messages before formatting.

each packet queue is limited to 20 seconds. consumers use the shared 3-second startup and rebuffer threshold. curl keeps at most 1 MiB of response data per track. packet queues, curl buffers, socket buffers, and native decoder memory are separate limits.

the timeline shows buffered media through the earlier audio/video packet end. it updates while paused and clears on a seek. the display uses available media timestamps, not an estimate from transfer speed.

the app uses `curl-auto`: libcurl prefers HTTP/3 with its normal connection fallback. a failed range can retry once on a fresh TCP connection, then that track keeps TCP. receive errors, partial transfers, timeouts, and QUIC errors can retry; cancellation cannot. partial bytes never reach the demuxer, and a failed retry remains a reader error even if the demuxer reports EOF. temporary redirects do not replace the source URL for later ranges.

explicit diagnostic controls are `ffmpeg`, `curl-reuse` for HTTP/1.1, `curl-h3` for HTTP/3 only, and `curl-auto` for the app behavior. strict HTTP/3 diagnostics do not switch protocols.

with decoder pre-roll enabled, the reader accepts H.264, HEVC, VP9, or AV1 video and AAC-LC audio. it retains video packets needed after a seek and resets framing so a new decoder gets the required parameter sets. the app selects formats within the installed decoder capability limits. AV1 was reported unavailable on the tested B9.

the normal app uses this reader and native decoder through managed app startup. it does not write HLS playlists or run a local media server. playback at 1× has displayed 4K SDR and 4K60 PQ HDR on the TV, with user confirmation of video and audio. pause, resume, and forward/backward seeks have also been checked.

buffer-stream loads set `option.transmission.trickType` to `client-side`. LeanTube owns the packet input and seeks. this setting selects seamless native rate changes instead of a pipeline seek that flushes the supplied packets and can stall playback. the original timestamp callbacks, one-second feed window, and buffer limits stay unchanged.

curl uses its OpenSSL QUIC backend, which upstream marks experimental. delivery success on one source does not prove reliability on every network.

## tests

run `just test-reader-http`. the local server supplies real H.264, HEVC, VP9, AV1, and AAC data in host memory, partial responses, and redirects. tests check packet framing, queue limits, seek cancellation, URL ownership, retry limits, and worker cleanup. command-line test programs are in the separate `diagnostics` package. these tests do not prove displayed video, audible audio, or HDR output.
