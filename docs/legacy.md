# webOS 3.x compatibility build

## install

both builds use the [same Homebrew Channel feed](https://github.com/hyperpuncher/leantube/releases/latest/download/repo.json).
choose one build for your TV:

| app                  | app ID                             | tested firmware   |
| -------------------- | ---------------------------------- | ----------------- |
| LeanTube             | `org.hyperpuncher.leantube`        | B9, webOS 4.9     |
| LeanTube (webOS 3.x) | `org.hyperpuncher.leantube.legacy` | UJ630V, webOS 3.5 |

the default build is intended for newer firmware, not only the B9.
the legacy build is intended for older webOS 3.x firmware, not only the UJ630V.
other models and firmware versions still need device tests.

the builds have separate app IDs, account data, and image caches. switching builds
requires signing in again. both can be installed, but most users need only one.
neither app replaces either installed YouTube app.

## build and release

run `just setup` to build the pinned SDK dependencies and the ARM32 soft-float
Odin compiler. all build and package tasks below run without TV access.

| task                  | result                                  |
| --------------------- | --------------------------------------- |
| `just build-release`  | default app in `build/app/`             |
| `just build-legacy`   | legacy app in `build/legacy/app/`       |
| `just package`        | default IPK in `build/`                 |
| `just package-legacy` | legacy IPK in `build/legacy/`           |
| `just release`        | both IPKs in `build/release/<version>/` |

the build script selects the legacy profile with `WEBOS_PROFILE=legacy`.
it sets the compiled app ID and package metadata together. separate package
staging directories prevent one build from replacing the other's files.

both builds use the version in `app/appinfo.json`. `just release` creates local
packages only. a manual workflow run saves build artifacts only. publication
requires a pushed version tag.

the release workflow uploads both IPKs to a draft GitHub release. it then uses
GitHub's asset hashes and sizes to create one `repo.json`. feed links use the
version tag because draft asset URLs are temporary. release notes keep the
commit-based `feat`, `fix`, and other groups with commit links. the workflow uploads the feed before it publishes the release, so the
existing feed URL changes only after all files are ready.

## image cache

both builds default to a **64 MiB disk image cache**. this is a maximum, not a
space reservation. it is separate from the **64 MiB decoded texture cache in RAM**.
the disk cache removes the oldest-saved images when it needs space. cache hits
do not update their age. failed cache writes do not prevent image display.

use `IMAGE_CACHE_MIB=128 just build-legacy` to override the disk limit. the same
override works with `just build-release` or `just release`. accepted values are
0 through 256. zero disables new disk image writes. startup trimming removes
cached `.image` files only, not account data.

## playback resume

Opening a partially watched video resumes at its supplied YouTube playback-action
timestamp when available, or estimates the position from the thumbnail's watched
percentage and duration. The percentage fallback is approximate, not an exact saved
time. Signed-in playback retains the last presented position in the current
catalog; reloading the catalog uses YouTube's metadata again. This behavior applies
to both builds.

Unwatched and completed (100% watched or at the known end) videos start at zero.
Without a known duration, percentages cannot be converted to a time, but a valid
supplied timestamp is retained. Live/upcoming cards remain unsupported.
Explicit launch positions (including zero), seeks, and quality changes are not
replaced by automatic resume. SponsorBlock can advance the initial position past
a sponsor segment. The desktop preview shows UI state only, not video playback.

## firmware compatibility

the legacy profile uses native lifecycle interface version 1
(`registerNativeApp`). both profiles select the Starfish C++ string ABI by
available symbols and bundle the SDK dual-ABI C++ runtime inside the app.
they do not replace firmware libraries and retain the installed EGL adapter.
the UJ630V ACB task-pointer signatures were checked against its firmware, not
inferred from the TV model.

the legacy profile binds `wl_seat` at protocol version 1, matching the firmware
SDL2 binding instead of the advertised version 4. with seat version 4, no key
events reached the app on the UJ630V. one such trial coincided with input loss
in other apps until a power cycle; the cause was not confirmed. with version 1,
the contributor confirmed physical-remote navigation. the default profile
keeps SDL's default seat version.

the tested legacy Starfish firmware has no video-capability query. the legacy
profile uses the UJ630V test limits directly: H.264 up to 1080p60 and VP9,
including Profile 2 HDR10, up to 2160p60. HEVC is not offered by this profile
because YouTube supplied no HEVC formats to test. AV1 is excluded: the UJ630V
accepted an AV1 load and advanced its clock, but displayed black. the default
profile queries the firmware for its codec limits.

## contributor test results

the contributor reported these results on the UJ630V with webOS 3.5. most input
tests used the official LG network remote:

- grid navigation, search with the system keyboard, OK/Back, pause/resume, and
  forward/backward 10-second seeks worked. Back stopped playback and unloaded
  the decoder.
- H.264 at 1920×818 and 1280×720, both at 24 fps with AAC stereo, decoded.
  captured display frames matched the source at the reported positions.
- leaving for another app exited LeanTube with no media pipelines left.
- viewer checks of audio output, A/V sync, smoothness, aspect fit, and physical
  OK/Back were still pending.

| format on UJ630V              | reported result                          |
| ----------------------------- | ---------------------------------------- |
| H.264 1080p60                 | real time, 0 dropped, source-frame match |
| VP9 2160p60 SDR               | real time, 0 dropped, source-frame match |
| VP9.2 HDR10 1080p60 / 2160p60 | real time, 0 dropped, source-frame match |
| AV1 1080p60                   | black output                             |
| HEVC                          | untested                                 |

viewer checks of 4K60 smoothness, HDR tone mapping, and audio were still pending.
these reports do not replace playback and seek tests after changes to the
native player or its runtime libraries.

live replays without index ranges fail. live entries remain unsupported.
