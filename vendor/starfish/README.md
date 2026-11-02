# Starfish C interface

source: https://github.com/mariotaku/ss4s

revision: `dfba721b85420ccabf91dac65be73984bf1865f9`

the C interface is copied from the upstream SMP wrapper. LeanTube adds small calls for native seeks, playback rate, and installed video capability limits. optional LG functions use weak references and return false when unavailable. no playback logic is added to C++.

the [LeanTube API notes](../../docs/starfish.md) describe the boundary, verified request options, and where to find the broader SDK interface. declared or exported methods are not necessarily usable in every pipeline.

license: LGPL-3.0. the license is in `LICENSE.txt`. the package also includes the GNU GPL version 3 text.

this small interface lets Odin call the installed LG C++ library without copying a C++ object or `std::string` layout into Odin. it contains no playback logic. the app and decoder test link it as a separate, replaceable shared library.

build with `just build` or `just package`. use `just bench-install` only for explicit diagnostics. the build uses the pinned webOS SDK headers and compiler. the TV supplies `libplayerAPIs.so.1`; firmware libraries are never copied into the package. the SDK's dual-ABI `libstdc++.so.6` is bundled app-locally (GPL-3.0 with GCC Runtime Library Exception 3.1) without replacing the installed runtime. `string_abi.cpp` is compiled separately for old and new libstdc++ string ABIs; exported API symbols select the matching compiler-generated return storage and destructor at runtime. a present capability-query API remains authoritative. legacy firmware lacking that API reports only a conservative H264 1080p30 limit; `StarfishMediaAPIs_legacyLimits` identifies such firmware so the app can apply its separately verified legacy profile. `just test-native` exercises both ABIs with ASan/UBSan, including missing queries. replace the wrapper by building the same C interface and replacing the app-private shared library while the app is closed. the build recipe is in the project build script.
