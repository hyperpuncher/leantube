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
`just test-youtube` checks live search, a cover, and direct stream access locally.
`just test-sponsorblock` checks real Linus Tech Tips sponsor data and skip targets,
without playback or skip-count reports.
`just run` opens the installed app on the TV.
`just capture 3840 2160` requests a capture at the specified size.

playback currently selects a direct H.264/AAC MP4. the verified test stream is
360p. 4k with synchronized audio is not complete. streams that require SABR or
login produce an error. TV text entry and the new playback path still require
device checks.

sponsor skipping uses [SponsorBlock](https://sponsor.ajay.app/) data under
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).
only sponsor segments are skipped. lookup sends a four-character hash prefix,
not the exact video ID. TV skip behavior still requires device checks.

local development supports Linux x86-64 and uses the installed SDL3,
SDL3_ttf, SDL3_image, curl, and OpenSSL libraries.
`just setup-tv-images` prepares the private TV image library once; normal
builds do not download or build it.
