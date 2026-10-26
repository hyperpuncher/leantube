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
just browse "Blender open movies"
just stop
```

`just dev` opens a local Wayland UI preview. it uses the prepared catalog and
covers, or 24 generated cards if no catalog is available. use the arrows, enter,
mouse, and escape to test the UI. it does not play media or contact the TV.
`just run` opens the installed app on the TV.
`just capture 3840 2160` requests a capture at the specified width and height.

local development supports Linux x86-64 and uses the installed SDL3,
SDL3_ttf, and SDL3_image libraries.
`just setup-tv-images` prepares the app-private TV image library once; normal
builds do not download or build it.

search and stream resolution are still host-prepared with yt-dlp. this is a
prototype limitation, not the intended standalone app workflow.
