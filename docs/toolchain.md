# B9 toolchain

## target

the B9 kernel reports `aarch64`, but this app uses ARM32 EABI5 soft-float.
the tested firmware has glibc 2.24. do not infer the app ABI from the kernel
name, and do not replace the TV's glibc or graphics libraries.

stock Odin ARM32 builds are not suitable for this target. the current build
uses a small experimental compiler patch. its validation is limited to the
device tests described in [verification](verification.md).

## local configuration

`just check` and `just test` use the installed host compiler.
`just build` uses these optional overrides:

| variable | default |
| --- | --- |
| `WEBOS_SDK` | `.cache/webos/sdk` |
| `WEBOS_ODIN` | `.cache/webos/odin/odin` |
| `WEBOS_PLATFORM` | `.cache/webos/platform` |
| `TV_HOST` | SSH alias `tv` |

the migration populated the ignored cache on this workstation with the
tested inputs. the SDK was copied and relocated to its new location.
the compiler's `base`, `core`, `vendor`, and `shared` collections are beside
its executable. the tracked build scripts do not refer to the old temporary
prototype folder.

`TV_APP_UID` is device-specific and must be set in the ignored `.env` before
`just run`. the stream request is copied with mode 0600 and ownership matching
that native app UID. do not make the request world-readable to bypass a
permission error. on this B9, the original prototype used UID 6533 and GID 5000.
after a first launch, the owner of `/tmp/leantube.log` identifies the runtime
UID. a launch without a request exits after logging that the request is missing.

## pinned inputs

| component | revision |
| --- | --- |
| Odin source | `8ac16fbfa20a58fb5bacb410ffd844b672753c6d` |
| SDL3 3.4.18 | `829a65d769d935c4852f8159e964312c0957260a` |
| Wayland 1.23.1 | `a9fec8dd65977c57f4039ced34327204d9b9d779` |
| Clay | `e6cc36941ab2af5d81107617039d6f527a1c660b` |
| webOS CLI | `@webos-tools/cli@3.2.6` |
| SDK release | `openlgtv/buildroot-nc4 webos-a38c582` |

SDK archive:
`arm-webos-linux-gnueabi_sdk-buildroot-x86_64.tar.gz`.

SHA256:
`04ad3311b48b4557a7002aef56ae2e167478e8e129f37daac04649bddf813616`.

upstream sources:

- [Odin](https://github.com/odin-lang/Odin)
- [SDL](https://github.com/libsdl-org/SDL)
- [Wayland](https://gitlab.freedesktop.org/wayland/wayland)
- [SDK release](https://github.com/openlgtv/buildroot-nc4/releases/tag/webos-a38c582)

this initial project setup consumes prepared toolchain inputs. it does not
yet automate rebuilding the complete SDK, compiler, Wayland, or SDL stack
from a clean machine.

## required cache contents

```text
.cache/webos/
  sdk/
    bin/arm-webos-linux-gnueabi-gcc
    bin/pkg-config
    arm-webos-linux-gnueabi/sysroot/
  odin/
    odin
    base/
    core/
    vendor/
    shared/
  platform/
    device-link/
      libluna-service2.so
      libAcbAPI.so
      libjson-c.so.2
    runtime/
      libSDL3.so.0
      libwayland-client.so.0
      libwayland-cursor.so.0
      libwayland-egl.so.1
      libxkbcommon.so.0
      libffi.so.8
      libatomic.so.1
      libgcc_s.so.1
```

the SDK sysroot includes the installed Wayland 1.23.1 development files.
SDL window setup uses Odin's `vendor:sdl3` bindings. the native bridge does
not include SDL headers.

`device-link/` contains host-side references copied from this TV. they are
used for linking, not placed in the package. the app uses the TV's existing
ACB and LS2 libraries at runtime.

`runtime/libwayland-egl.so.1` is the B9's original
`/usr/lib/libwayland-egl.so.0`, stored under the filename SDL3 loads.
its old window layout is required by the B9 graphics driver. the newer
Wayland client library is private to the app. these cached device-specific
files are not a portable SDK or a general release bundle.

## patches and native API limits

- `patches/odin-arm32-softfp.patch` selects the base ARM32 calling convention
  and disables homogeneous float aggregate handling for this target.
- `patches/sdl3-b9.patch` guards a missing data device when keyboard focus
  leaves a window. without it, closing the native window crashes.
- the B9 ACB video-metadata function has a task-output pointer absent from
  the SDK header. the native bridge uses the signature checked in the
  device binary.
- the bridge creates a standard `wl_shell_surface`, then adds the LG shell
  extension. native media metadata must use the B9's nested video format.

copying an SDK to another path requires its `relocate-sdk.sh` script.
keep these inputs outside git, and do not update TV system libraries.
