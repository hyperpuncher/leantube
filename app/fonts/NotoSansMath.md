# Noto Sans Math

`NotoSansMath.ttf` is a subset of Noto Sans Math Regular, version 3.000.
SDL_ttf uses it only for glyphs missing from earlier fallback fonts.

- source: <https://github.com/notofonts/math>
- input: `NotoSansMath-Regular.ttf` from Arch Linux `noto-fonts` 1:2026.11.01-1
- input SHA256: `d51afd5739c7ba6c44fcab35a88160e25dfb69a2d4ad0bd99533f8d894af1f96`
- license: SIL Open Font License 1.1, see `OFL.txt`
- ranges: U+1D400–U+1D7FF (Mathematical Alphanumeric Symbols) and
  U+2100–U+214F (Letterlike Symbols)

The subset includes styled letters used in some YouTube titles. It keeps all
996 characters that the source font has in the mathematical alphanumeric block.

regenerate with fontTools:

```sh
pyftsubset NotoSansMath-Regular.ttf \
    --unicodes=U+1D400-1D7FF,U+2100-214F \
    --layout-features='' --no-hinting --desubroutinize \
    --output-file=app/fonts/NotoSansMath.ttf
```
