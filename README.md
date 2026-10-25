# leantube

a native YouTube playback prototype for the rooted LG B9, built with Odin,
Clay, SDL3, native Wayland, and the TV's media services. no browser is used.

## current scope

- direct YouTube H.264/AAC playback, with video and audio
- pause/resume, 10-second seek controls, and speed requests
- Clay control bar with confirmed playback state, position, and duration
- real video speed measured at about 2x by comparing TV captures with source frames

this is not a complete YouTube client. a host runs `yt-dlp` to resolve a fresh
stream URL; the TV downloads and decodes the video itself. the current test
selects a 360p combined stream. each run still stops after three minutes.
standby/wake testing is pending.

## development

host checks need `odin`, `just`, `odinfmt`, `clang-format`, and `shellcheck`.
`just test` also uses a C compiler (`cc`) and `ar` for the headless Clay check.
TV builds need the prepared B9 toolchain described in [toolchain setup](docs/toolchain.md).

```sh
just             # list tasks, without launching anything
just fmt
just check
just test
just build       # stage build/app/leantube and its private libraries
just package     # create an ARM IPK in build/
```

packaging uses Bun to install the pinned webOS CLI into the ignored local
tools cache. build scripts also use Bash, jq, and trash. nothing is installed
globally.

## TV commands

configure the SSH alias and native app UID in an ignored `.env` file:

```sh
cp .env.example .env
# set TV_HOST and TV_APP_UID for your TV
just install
just run                      # fresh Big Buck Bunny stream
just logs
just status                   # only this app's media resources
just capture                  # only when this app is in the foreground
just stop
```

`just run <video-id>` selects another public video, if it has format 18.
resolution requires `yt-dlp`; deployment requires SSH and SCP access to a
rooted TV. keep the signed request file private.

the app keeps the separate ID `org.hyperpuncher.odin.tv.prototype`.
installation does not replace either YouTube app. no system library,
firmware, startup service, or remote binding is changed.

## layout

- `src/`: Odin player, metadata parsing, and Clay controls
- `src/native/`: LS2, LG Wayland, and ACB bridge, plus the Clay implementation
- `vendor/clay/`: pinned Clay header and Odin binding, with license
- `app/`: package metadata and icon
- `scripts/`: build, resolution, installation, and TV commands
- `tests/layout/`: headless C/Odin layout check for the host and TV
- `patches/`: experimental compiler ABI and SDL3 B9 fixes

see [verified results and limits](docs/verification.md).
