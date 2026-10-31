# Starfish C interface

source: https://github.com/mariotaku/ss4s

revision: `dfba721b85420ccabf91dac65be73984bf1865f9`

the C interface is copied from the upstream SMP wrapper. LeanTube adds small calls for playback rate and installed video capability limits. optional LG functions use weak references and return false when unavailable. no playback logic is added to C++.

license: LGPL-3.0. the license is in `LICENSE.txt`. the package also includes the GNU GPL version 3 text.

this small interface lets Odin call the installed LG C++ library without copying a C++ object or `std::string` layout into Odin. it contains no playback logic. the app and decoder test link it as a separate, replaceable shared library.

build with `just build` or `just package`. use `just bench-install` only for explicit diagnostics. the build uses the pinned webOS SDK headers and compiler. the TV supplies `libplayerAPIs.so.1` and its C++ runtime; neither system library is copied into the package. replace the wrapper by building the same C interface and replacing the app-private shared library while the app is closed. the build recipe is in the project build script.
