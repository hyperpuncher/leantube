# verified results and remaining tests

the original prototype was tested on a rooted OLED65B9SLA with firmware
05.40.45 and webOS SDK 4.10.0. the source is now in this repository.

## confirmed on the TV

- native Wayland window and OpenGL ES rendering through SDL3
- direct YouTube H.264/AAC video and audio playback
- seek and speed changes through the physical remote
- a Clay control bar with playback state and timestamps
- duration read from `sourceInfo.programInfo[0].duration`, in milliseconds
- pause/resume events reflected by the control bar
- media unload acknowledged on close, followed by an empty app pipeline list
- compatible C/Odin structure sizes and a bottom-aligned layout regression check

the duration parser also has two host tests covering the observed metadata
and missing, empty, negative, zero, and nonnumeric duration values.

## speed measurement

TV DISPLAY captures were matched against the same YouTube format-18 video.
the comparison excluded the top debug text strip and used FFmpeg SSIM at
ten source frames per second.

| request | displayed source advanced | approximate wall time |
| --- | --- | --- |
| 1x | 12.5 seconds | 12.45 seconds |
| 2x | 25.3 seconds | 12.53 seconds |

capture requests each took about two seconds, so the midpoint estimates are
not precise rate measurements. the timing bounds still exclude 1x for the
fast run. this proves changed visible video speed, not just a reported
media clock. the user also confirmed speed changes through the native
remote-control path.

## limits

- complete YouTube resolution still runs on the host through `yt-dlp`
- the test currently requests a combined 360p stream
- each run has a three-minute automatic stop
- standby/wake has not yet been verified for this app
- intermediate and slower rates, long-run sync, and pitch quality need more tests
- a Wayland queue warning remains at process exit
- the B9's Odin test runner attempt stopped with an illegal instruction;
  the metadata tests pass on the host, and the real app reads the duration
  correctly on the TV. do not claim general ARM32 runtime certification
- the prepared compiler and native library cache are required; a full
  clean-machine toolchain bootstrap is not automated yet

`just test-tv-layout` runs a small headless layout executable on the TV.
it does not open a window, register an app, play media, or change settings.

the source move changes the package entry point to `leantube` and diagnostic
paths to `/tmp/leantube.log` and `/tmp/leantube.pid`. the new package needs
installation before the new TV run commands can be used. the previous
installed prototype is not silently overwritten during project setup.

## repository migration checks

- `just fmt`, `just check`, and the two metadata tests pass
- `just build` produces ARM32 EABI5 soft-float with `$ORIGIN/lib` search paths
- `just package` produces the version-0.0.4 ARM IPK without a stream request
- `just test-tv-layout` passes on the TV from the project-local toolchain
- installer stream handling was checked with an isolated SSH boundary:
  success completes, rejection fails, and an acknowledgement alone fails

at the end of the migration step, version 0.0.4 had not yet been installed
or playback-tested as a package. the device checks below were done later.

## cleanup checks

SDL window creation and property access now use Odin's existing bindings.
the C bridge keeps LS2, GLib, LG Wayland roles, and ACB integration. the
separate C diagnostic probe is removed. both layout test targets use the
same C/Odin size check and assert the computed bottom-panel bounds.

- `just fmt`, `just check`, and `just test` pass
- `just test` runs the headless layout check on the host, two metadata tests,
  and three installer completion checks
- the updated ARM32 soft-float app and IPK build successfully
- a rebuild removes stale files from package staging, while preserving the
  private stream request outside that directory
- the package contains neither the private request nor the stale test files

the first device test attempt was blocked by an SSH timeout. the TV was
then turned on, and the updated package was tested as described below.

## packaged device checks after cleanup

- the updated ARM32 layout test passes: C/Odin sizes are 72 bytes for a
  render command, 204 bytes for an element declaration, and 20 bytes for
  error data
- the installer reports completed installation of version 0.0.4
- the installed executable matches the local build, SHA256
  `cfa388e4ff2cd2143bcd0a62197d6e18f6a3c953e1646b5bea6aa0d85e4f13b6`
- DISPLAY captures show video and the Clay controls through the Odin window
  setup; the user confirmed working audio
- seek requests change the displayed scene; paused video captures about
  4.65 seconds apart are identical above the control bar, with SSIM 1
- resume and speed changes advance actual displayed video frames
- closing through `closeByAppId` produces an unload acknowledgement; the
  player process is gone, and its media pipeline list is empty
- the private request remains mode 0600, owned by native UID 6533 and GID 5000

source-frame matching at ten frames per second, excluding the control bar:

| request | displayed source advanced | approximate wall time |
| --- | --- | --- |
| 1x | 12.9 seconds | 12.87 seconds |
| 2x | 25.8 seconds | 12.88 seconds |

the matching frames have SSIM scores from 0.949 to 0.980. capture requests
last about 2.1 to 2.3 seconds. even the broad capture-time bounds exclude
1x for the fast run; do not treat the midpoint ratio as a precise rate.

these checks send seek, pause, play, and rate requests directly to the
media service. they do not retest physical remote or pointer input. the
rate label remains at 1x when the service rate is changed outside the app.

one UI issue remains: after a seek followed immediately by pause, the
elapsed label can retain its earlier position. the paused frame matched
source time 296.6 seconds after a 300-second seek request, while the label
still showed 00:02. playback events update the label again after resume.
seek precision and paused-position updates need a separate fix.

the player was explicitly closed after the tests, not left running in the
background. no standby test was done. the exit-time Wayland queue warning
and the missing XKB Compose-file warning remain.
