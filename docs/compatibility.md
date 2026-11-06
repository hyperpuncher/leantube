# builds and webOS compatibility

## install

the app uses the [Homebrew Channel feed](https://github.com/hyperpuncher/leantube/releases/latest/download/repo.json).

| app      | app ID                      | tested firmware                |
| -------- | --------------------------- | ------------------------------ |
| LeanTube | `org.hyperpuncher.leantube` | B9 webOS 4.9, UJ630V webOS 3.5 |

other models and firmware versions still need device tests, including webOS 5.

the app does not replace either installed YouTube app. it keeps its account data
and image caches under its own app id.

the earlier separate `org.hyperpuncher.leantube.legacy` package is gone. install
**LeanTube** instead. the feed no longer offers the legacy id, and the old
package is not updated.

## build and release

run `just setup` to build the pinned SDK dependencies and the ARM32 soft-float
Odin compiler. all build and package tasks below run without TV access.

| task                 | result                            |
| -------------------- | --------------------------------- |
| `just build`         | development app in `build/app/`   |
| `just build-release` | optimized app in `build/app/`     |
| `just package`       | IPK in `build/`                   |
| `just release`       | IPK in `build/release/<version>/` |

[`app/appinfo.json`](app/appinfo.json) supplies the app id, version, and package
metadata. `just release` creates a local package only. a manual workflow run
saves a build artifact only. publication requires a pushed version tag.

the release workflow uploads the IPK to a draft GitHub release. it then uses
GitHub's asset hash and size to create `repo.json`. feed links use the version
tag because draft asset URLs are temporary. release notes keep the
commit-based `feat`, `fix`, and other groups with commit links. the workflow
uploads the feed before it publishes the release, so the existing feed URL
changes only after all files are ready.

## image cache

the app defaults to a **64 MiB disk image cache**. this is a maximum, not a
space reservation. it is separate from the **64 MiB decoded texture cache in RAM**.
the disk cache removes the oldest-saved images when it needs space. cache hits
do not update their age. failed cache writes do not prevent image display.

use `IMAGE_CACHE_MIB=128 just build-release` to override the disk limit. the
same override works with `just release`. accepted values are
0 through 256. zero disables new disk image writes. startup trimming removes
cached `.image` files only, not account data.

## firmware compatibility

one code path covers the tested firmware. the differences below are selected at
runtime, not at build time.

- lifecycle: the package declares interface version 1 and registers with
  `registerNativeApp` on every firmware. version 1 exists from webOS 3.x, and
  the tested 4.10 firmware still accepts it. replies are read from either
  `message` or `event`.
- video plane: `libAcbAPI` is loaded with `dlopen`, so it is never a link-time
  dependency. webOS 5 removed the library. there the app exports a
  `webos_foreign` window, passes its id as `option.windowId` in the Starfish
  load request, and sets the source and destination regions after load. a
  firmware with neither mechanism starts, then reports the playback failure
  instead of failing to load.
- window: the window is created without high pixel density. webOS 3.5 rejects
  `wl_surface.set_buffer_scale`, and SDL sends it when high pixel density is
  requested, so the surface never attaches. every tested compositor runs at
  scale 1, so the flag is not needed.
- seat: `wl_seat` is bound at protocol version 1 everywhere. with seat version 4,
  no key events reached the app on the UJ630V. one such trial coincided with
  input loss in other apps until a power cycle; the cause was not confirmed.
  the B9 advertises seat version 2 and repeated key tests pass at version 1.
- codec limits: the app always asks the firmware with `videoLimits` and falls
  back to the UJ630V test table when the query is absent. the table keeps
  H.264 up to 1080p60 and VP9, including Profile 2 HDR10, up to 2160p60. HEVC
  is not offered there because YouTube supplied no HEVC formats to test. AV1 is
  excluded: the UJ630V accepted an AV1 load and advanced its clock, but
  displayed black.
- seek: plain milliseconds on every firmware. webOS 3.x parses the message with
  `strtoll` and rejects JSON; on the B9 the picture stays until the new frame
  arrives.
- Starfish C++ string ABI is selected by available symbols. the SDK dual-ABI C++
  runtime is bundled inside the app. firmware libraries are not replaced, and
  the installed EGL adapter is used through an app-private `.so.1` alias.
- the UJ630V ACB task-pointer signatures were checked against its firmware, not
  inferred from the TV model.

webOS 5.x startup and playback still need device confirmation. a tester
reported the missing library on webOS 5.3, and a second tester has webOS 5.5.
webOS 3.5 also needs a re-test after the runtime selection changes.

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
these reports were collected before the runtime selection above and do not
replace playback and seek tests after changes to the native player or its
runtime libraries.

live replays without index ranges fail. live entries remain unsupported.
