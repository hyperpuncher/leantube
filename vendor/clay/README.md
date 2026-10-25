# Clay source

the header is pinned to Clay revision
`e6cc36941ab2af5d81107617039d6f527a1c660b`.

the Odin binding comes from the tested Spoti binding for that header.
LeanTube changes its foreign library declaration to `system:clay` so the
build links the C object compiled for the target, not a desktop archive.
there are no prebuilt Clay libraries in this directory.

the upstream zlib/libpng license is preserved in LICENSE.md and the header.

upstream: https://github.com/nicbarker/clay
binding reference: https://github.com/hyperpuncher/spoti
