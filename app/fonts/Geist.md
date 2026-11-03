# geist

source: [vercel/geist-font](https://github.com/vercel/geist-font), version 1.800.

this is the upstream variable `Geist[wght].ttf`. its `tnum` OpenType feature is
frozen into the character map so digits use the fixed-width `.tf` glyphs:

```sh
uvx --from opentype-feature-freezer pyftfeatfreeze -f tnum Geist-upstream.ttf Geist.ttf
```

the names, the `wght` axis, all glyphs, and all metrics stay as upstream. times,
durations, rates, and login codes therefore keep one digit width without a
second font. the font uses the SIL Open Font License 1.1 in `OFL.txt`.
