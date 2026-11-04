# display and UI resolution

the TV gives apps a 1920×1080 graphics plane and enlarges it to the panel. this
file records what that limit is, where it lives, and what was tested while
looking for a way around it. it applies to both builds.

## what the app draws at

the app draws at the compositor size, 1920×1080. that is the full graphics
plane on tested TVs, not a setting LeanTube chose.

requesting a 3840×2160 window was tested on the B9 and reverted. the renderer
and pixel readback reached 3840×2160, but `/proc/lg/fbdev/osdinfo` still
reported OSD 0 input at 1920×1080 and output at 3840×2160. the compositor
reduced the 4K buffer back to 1080p before the panel enlarged it, so the extra
pixels added cost without detail.

### where the limit lives

read-only measurements on the B9, webOS 4.9, firmware 04.04.35:

| source                                         | value                 |
| ---------------------------------------------- | --------------------- |
| `fb0/status` `hw_disp`                         | 3840×2160             |
| `fb0/status` `hw_gfx`                          | 1920×1080             |
| `osdinfo` OSD 0 input / output                 | 1920×1080 / 3840×2160 |
| `osdinfo` `info.fix.smem_len`                  | 16588800 bytes        |
| `fb0/virtual_size`                             | 1920,2160             |
| `GM_GetGraphicResolution`                      | 1920×1080             |
| `GM_GetWindowMaxResolution` on LG's EGL window | 1920×1080             |

`1920 × 1080 × 4 × 2 = 16,588,800`, so the framebuffer is exactly a
double-buffered 1080p allocation. `GM_SetWindowResolution` rejects sizes above
the window maximum, and the graphics manager sets its output resolution from
firmware board info at startup.

`libdile_boardinfo` supports graphic modes 1920×1080, 2560×1080, 3840×2160 and
5120×2160, but selects one from a board-info index initialised at boot from
`/etc/starfish/model_id` and firmware data. nothing at runtime selects it.

allocation is not the blocker: a test program calling `GM_CreateSurface` at
1920×1080, 2560×1080, 3840×2160 and 5120×2160 succeeded for every size. the
limit is the configured graphic resolution and framebuffer size, not the GPU or
memory pool.

### compositor environment was tested and ignored

`/etc/init/surface-manager.conf` exports `STARFISH_WINDOW_WIDTH=1920` and
`STARFISH_WINDOW_HEIGHT=1080`. a bind-mounted copy over the read-only rootfs set
them to 3840 and 2160, then `initctl restart surface-manager` ran. the
compositor restarted normally and OSD 0 input stayed 1920×1080, so the retail
`starfish` QPA plugin ignores those variables and uses the graphics-manager
resolution. the mount, files and restart were reverted; nothing persisted.

### model tier

the configd key `com.webos.surfacemanager.compositorGeometry` selects the
compositor size and is absent here. only LG's 8K-class model layers override it
to 3840×2160. 4K sets in this generation, including this B9, ship a 1080p UI
that the display hardware enlarges.

a 4K UI would need the graphics manager and its kernel driver to advertise and
reserve 4K. that is firmware work, not an app setting.

### configuration paths that were checked

the board-info library parses `/proc/cmdline` (`ToolOpt=`, `modelName=`,
`modelopt=`, `debugMode=`), `/etc/starfish/model_id`, and
`/mnt/lg/model/RELEASE.cfg` (`alNum=`, `serialNum=`, `hwopt=`). the graphics
manager reads the same release file for only `modelName` and
`szCountryGroupCode`. the file also contains `eOSDResolution,0x556300`, but no
installed library reads that key, so it is legacy data rather than a control.

`DILE_BOARDINFO_GetGraphicResolution` selects its result from a value at
`boardinfo + 0x80`, covering 1280×720, 1920×1080, 2560×1080, 3840×2160 and
5120×2160. nothing in `libdile_boardinfo` writes that field, so it is filled
before userspace configuration is parsed.

the kernel has the display driver built in: `/proc/kallsyms` lists the
`GFX_*` surface API and the OSD register setup for this SoC (`DE_REG_M19_OSD_Init`,
`DE_HAL_OSD_Init`, `BE_TOP_HW_M19_*`) alongside Mali and the DAC drivers. no
separate module file exists for it, and it exposes no OSD-size module parameter.
changing the graphics plane size therefore means changing the kernel, not a
file on the TV.

this limit applies to the graphics plane only. video keeps its separate plane
and still plays 2160p, including HDR.
