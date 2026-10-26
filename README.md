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
the full-height left column has the avatar, search, subscriptions, watch later,
home, playlists, and liked-video icons. left from the first card column selects the
icons; up and down select an icon; right returns to the cards. select search,
or press tab or `/`, to open the temporary field and LG keyboard. enter submits;
back cancels text entry. there is no permanent search field or logo.
signed-in startup opens subscriptions. subscriptions, watch later, home,
playlists, and liked videos load real YouTube TV feeds. playlist cards open
their contents; back returns to the playlist list. down from the final row,
or Load more, requests the next page. ad cards and live entries are omitted.
page and sidebar backgrounds are pure black; overflowing text ends with an ellipsis.

select the avatar to open the users window, or sign in if no account is active.
the TV shows a QR code and a short code. scan with a phone, or open
google.com/device and enter the code. tokens stay in the app directory with
mode 0600 and are sent only to YouTube over HTTPS. the users window contains
account switching, Add account, and Sign out. the network worker refreshes
access tokens on account selection and before feed requests when they expire.

`just dev` opens the local Wayland UI with real search and cover downloads.
local playback is UI-only. it does not contact the TV.
`just test-youtube` checks live search, a cover, direct MP4 access, and the
private 4k HLS master with its original AAC audio locally.
`just test-sponsorblock` checks real Linus Tech Tips sponsor data and skip targets,
without playback or skip-count reports.
`just run` opens the installed app on the TV.
`just capture` uses the tested B9 capture size, 1920×1080. optional width and height
arguments override it. the TV capture API requires dimensions and rejects 4k;
this is separate from video playback resolution.

playback prefers a visionOS HLS master, using the visitor session returned
by search or browsing. the session stays in worker memory and is not logged or saved.
YouTube often returns a large master with no audio renditions. the app rewrites
a private master with one highest variant and adds the original AAC track from
the player byte ranges. the private files are mode 0600 and deleted on stop.
if that API does not provide HLS, resolution falls back to a direct H.264/AAC MP4.
there is no fixed quality cap. the quality label uses the standard short-side
tier, so 3840×1920 is `2160p`, not a raw height.

B9 checks confirmed remote keyboard search, real covers, 4k playback for Linus
Tech Tips, audible AAC audio, seeking with synchronized audio, pause, Back, and
complete process/media cleanup. startup is about 2 to 3 seconds. the LG keyboard
adapter uses SDL-webOS text-model code and SDK-generated bindings. HDR, 4k60,
and long playback sessions still need checks.

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
