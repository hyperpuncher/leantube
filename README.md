# leantube

lightweight native YouTube client for webOS

## built with

- [odin](https://odin-lang.org/)
- [sdl3](https://www.libsdl.org/)
- [clay](https://github.com/nicbarker/clay)
- [sponsorblock](https://sponsor.ajay.app/)

## install

### homebrew channel

1. open Homebrew Channel and go to **Settings → Repositories → Add repository**.
2. enter this repository URL:

    ```text
    https://github.com/hyperpuncher/leantube/releases/latest/download/repo.json
    ```

3. select **Add repository**, then return to the app list.
4. open **LeanTube** and select **Install**.

## legacy webOS build (experimental)

`just setup` builds the pinned SDK dependencies and ARM32 soft-float Odin compiler.
`just build-legacy` stages an experimental webOS 3.x compatibility build;
`just package-legacy` writes its IPK under `build/legacy/` without TV access.
The normal build/package tasks keep the newer lifecycle defaults.

The legacy profile uses native lifecycle interface version 1 (`registerNativeApp`).
It does not replace firmware libraries. Both
profiles select the Starfish C++ string ABI by available symbols and bundle the
SDK C++ runtime app-locally. The installed EGL adapter is retained. The UJ630V
ACB task-pointer signatures were checked against its firmware, not inferred
from the TV model.

The legacy thumbnail cache defaults to 16 MiB (normal build: 256 MiB).
Override with e.g. `IMAGE_CACHE_MIB=8 just build-legacy`; accepted values are
0–256. Zero disables new disk image writes and startup trimming removes cached
`.image` files only, not account data. This is a cache ceiling, not a disk-space
reservation; failed cache writes do not prevent image display.

The legacy profile binds `wl_seat` at protocol version 1, matching the firmware
SDL2 binding rather than the advertised version 4. With seat version 4, no key
events reached the app on the UJ630V, and one such trial coincided with input
loss in other apps until a power-cycle (cause unconfirmed). With version 1, the
user confirmed physical-remote navigation. The normal profile keeps SDL's
default seat version.

Measured on the UJ630V (webOS 3.5), mostly via the official LG network remote:

- Grid navigation, search with the system keyboard, OK/Back, pause/resume and
  ±10 s seeking work. Back stops playback and unloads the decoder.
- H264 1920×818 at 24 fps and 1280×720 at 24 fps, with AAC stereo, decoded.
  Captured display frames matched the source at the reported positions.
- Leaving for another app exits LeanTube cleanly, with no media pipelines left.
- Not yet verified by a viewer: audio output, A/V sync, smoothness, aspect fit,
  and physical OK/Back.

Legacy Starfish firmware has no video-capability query, so the legacy profile
offers exactly the formats decoded and frame-checked on the UJ630V: H264 up to
1080p60 and VP9 (including Profile 2 HDR10) up to 2160p60. HEVC is not offered
because YouTube supplied no HEVC formats to test. AV1 is never offered: the
UJ630V accepted an AV1 load and advanced its clock but displayed black.

| Format (UJ630V)               | Result                                  |
| ----------------------------- | --------------------------------------- |
| H264 1080p60                  | Pass: real time, 0 dropped, frame match |
| VP9 2160p60 SDR               | Pass: real time, 0 dropped, frame match |
| VP9.2 HDR10 1080p60 / 2160p60 | Pass: real time, 0 dropped, frame match |
| AV1 1080p60                   | Fail: black output                      |
| HEVC                          | Untested                                |

Viewer judgement of 4K60 smoothness, HDR tone mapping and audio is pending.
Live replays without index ranges fail, as upstream treats
live entries as unsupported.
The app ID remains `org.hyperpuncher.leantube`, distinct from YouTube.
