# Starfish in LeanTube

the playback code is Odin. a small C++ adapter exposes the C-compatible calls
that the app needs. it does not contain playback logic or replace LG's library.

## code and SDK

- `src/starfish_linux_arm32.odin` declares the adapter calls, names the events
  handled by the app, and implements decoder input and lifecycle operations.
- `src/starfish_request.odin` defines the typed load request and its input values.
  the standard JSON encoder writes it without manual JSON formatting.
- `src/player_linux_arm32.odin` owns playback, seeking, pause, rate, and history.
- `vendor/starfish/StarfishMediaAPIs_C.h` declares the C interface and contains
  the broader event list copied from ss4s.
- `vendor/starfish/StarfishMediaAPIs_C.cpp` forwards calls and converts C++ string
  results to caller-owned C buffers. optional calls return false when absent.

we build against the [openlgtv/buildroot-nc4 community SDK](https://github.com/openlgtv/buildroot-nc4/releases/tag/2026.08-webos).
its archives are pinned in `scripts/toolchain.sources`. the broader C++ interface
is declared in `usr/include/starfish-media-pipeline/StarfishMediaAPIs.h` inside
the SDK's ARM32 sysroot. consult that header before assuming the adapter covers
every useful method.

the TV supplies `libplayerAPIs.so.1`. the app packages its own adapter and the
SDK dual-ABI `libstdc++.so.6` inside the app; it does not replace firmware
libraries. the SDK is not complete official LG API documentation. its
header contains opaque storage and padding assumptions; do not copy private
class layouts or vtables into Odin.

## verified request behavior

| call or load option                  | contract used by LeanTube                                                                                                                 |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `Seek`                               | JSON `position` is in milliseconds. `retainLastRenderedFrame:true` keeps the previous picture during a seek. webOS 3.x takes plain ms.    |
| load `option.seekMode`               | `"keep-rate"` prevents an explicit seek from resetting the selected playback rate.                                                        |
| load `option.transmission.trickType` | `"client-side"` avoids an unwanted pipeline seek when changing the rate.                                                                  |
| load `esInfo.ptsToDecode`            | initial target in nanoseconds, not the millisecond unit of `Seek.position`.                                                               |
| load `aacInfo.frequency`             | original sample rate in kHz; `profile:2` and `format:"adts"` describe AAC-LC framing, not transcoding.                                    |
| `SetPlayRate`                        | JSON `playRate` is a multiplier. `audioOutput:true` requests audio output during rate changes.                                            |
| `Feed`                               | `bufferAddr` is a hexadecimal address string, `bufferSize` is bytes, `pts` is nanoseconds, and `esData` is 1 for video or 2 for audio.    |
| feed reply                           | `Ok` accepts the packet. `BufferFull` or `Pending` retains it for another attempt. the adapter's boolean alone does not prove acceptance. |

preserve the native key spelling, including `seperatedPTS`. successful playback
verifies the current load combination, not the independent effect of every
field. inherited values such as `totalStreamSize:256` have no verified unit;
do not change them based only on their names.

seeks retain the decoder and display binding. paused seeks remain paused and
keep the old picture until resume; a paused target-frame preview is not an
implemented feature. stopping or changing the video unloads the pipeline.

## evidence and limits

read-only inspection of the tested TV's `Seek` implementation found the JSON
`position` and `retainLastRenderedFrame` fields. these options are not described
by the SDK's `Seek(const char *millis)` declaration. captures verified retained
pictures, and source-frame comparisons verified rate preservation. 4k SDR and
4k60 PQ HDR playback and seeking were checked. callback counts and successful
service replies alone are not display or speed proof.

webOS 3.5 `Seek` parses its message with `g_ascii_strtoll`, so JSON seeks to 0
and stalls playback.

the broader investigation found 33 SDK member declarations, 91 runtime member
names, 34 SDK events, and 137 `option.*` strings across the copied Starfish and
player-factory libraries. these are different evidence levels, not a complete
JSON schema. useful research candidates include `Preload`, `SelectTrack`, and
`renderPrerolledFrame`, but they are not verified application contracts.

SDK declarations and installed exports differ. for example, the copied library
has no `getVideoRenderQueueLength`, `getAudioBufferSize`, or `setHdrInfo` export.
`flush()` accepted a probe, while `setTimeToDecode` rejected the tested seek
path. symbol presence does not prove that a method works with a given pipeline.
HDR still works through the existing ACB display-metadata path.

before adding a call, check its declaration, installed availability, payload,
units, and actual result. do not add wrappers for unverified internal exports
or infer an option's type from a string scan. other firmware can differ; select
behavior by available APIs, not by a model name.

never log signed URLs, credentials, raw event strings, packet addresses, or
complete load/feed requests. keep copied device libraries and private requests
out of the repository and application packages.
