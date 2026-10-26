# Clay

vendored from upstream revision `e6cc36941ab2af5d81107617039d6f527a1c660b`.
this directory contains the upstream header, Odin binding, Linux x86-64 archive,
and license. unused platform archives and their import branches are omitted.
the binding has project formatting changes. Linux ARM32 uses the locally
compiled B9 library because upstream supplies no ARM32 soft-float archive.

local development does not compile Clay. the B9 build compiles the pinned
header and keeps the C/Odin ABI check.

upstream: https://github.com/nicbarker/clay
binding: https://github.com/nicbarker/clay/tree/main/bindings/odin/clay-odin
