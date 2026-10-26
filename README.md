# leantube

early native YouTube client for the rooted LG B9.
Odin + Clay + SDL3, on Wayland.

`just` lists the development tasks. configure `.env` from `.env.example`.

```sh
bun install
just fmt
just check
just test
just dev
just install
just run
just stop
```

search results, original cover images, and playback addresses now come from
native HTTPS requests. no host catalog or prepared stream files are required.
press up from the first row, press tab or `/`, or click the search field to
enter a query. enter submits; back cancels text entry.

`just dev` opens the local Wayland UI with real search and cover downloads.
local playback is UI-only. it does not contact the TV.
`just test-youtube` checks live search, a cover, direct MP4 access, and 4k HLS
manifests locally.
`just test-sponsorblock` checks real Linus Tech Tips sponsor data and skip targets,
without playback or skip-count reports.
`just run` opens the installed app on the TV.
`just capture` uses the tested B9 capture size, 1920×1080. optional width and height
arguments override it. the TV capture API requires dimensions and rejects 4k;
this is separate from video playback resolution.

playback now prefers a visionOS HLS master, using the anonymous session returned
by search. the session stays in worker memory and is not logged or saved.
if that API does not provide HLS, resolution falls back to a direct H.264/AAC MP4.
the app requests the video’s advertised maximum resolution and bitrate through
the TV media stack at startup, with no fixed quality cap. lower resolutions can be
selected when the source or connection cannot provide 4k. the quality label uses
the reported video height, not the largest playlist entry.

B9 checks confirmed remote keyboard search, real covers, 4k playback for Linus
Tech Tips, and changing captured frames. Spring played and sought at 2048×858.
pause, Back, repeated keyboard activation, and complete process/media cleanup
passed. startup took about 5 s with one audio track and about 15 s with six, so
media pipeline startup still needs work. the player selects the original audio
track when the service reports it. the LG keyboard adapter uses SDL-webOS
text-model code and SDK-generated bindings. audible audio, audio/video
synchronization, HDR, 4k60, and long playback sessions still need checks.

media-service playback failures remain errors; there is no hidden retry loop.
SABR-only or login-only replies produce an error. the B9 capture service rejected
3840×2160 as out of range; 1920×1080 capture worked. this does not establish a
limit on video decoding or UI rendering.

sponsor skipping uses [SponsorBlock](https://sponsor.ajay.app/) data under
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).
only sponsor segments are skipped. dark gray timeline ranges mark sections
that remain eligible for skipping; the red progress fill stays above them.
lookup sends a four-character hash prefix,
not the exact video ID. the B9 test confirmed a skip from 88.204 to 109.099 seconds
on Linus Tech Tips, with before/after frame captures.

local development supports Linux x86-64 and uses the installed SDL3,
SDL3_ttf, SDL3_image, curl, and OpenSSL libraries.
`just setup-tv-images` prepares the private TV image library once; normal
builds do not download or build it.
