# leantube agent notes

- use `just` for project tasks
- run `just fmt`, `just check`, and `just test` after changes
- use native Wayland, Odin, Clay, and SDL3
- keep B9 SDK and compiler inputs in the ignored toolchain cache, not in git
- the B9 app ABI is ARM32 soft-float, even though the kernel reports aarch64
- do not use the stock ARM32 Odin compiler for the TV build; see docs/toolchain.md
- preserve the separate prototype app ID and both installed YouTube apps
- do not change TV firmware, system libraries, startup services, or remote bindings
- announce any standby/wake test before interrupting the TV
- never log signed stream URLs, credentials, or complete load requests
- keep private stream requests mode 0600 and out of packages
- check actual displayed frames when testing playback speed
- after playback tests, close the prototype and verify its process and media pipelines are gone
- successful service replies alone do not prove video or completed installation
- do not commit, push, tag, or publish without permission
