# LG text model

`text.xml` comes from SDL-webOS, `wayland-protocols/text.xml`, revision
`ba4c86af391d1524d3ff0cb61dc3b10035933239`.
its license is in `app/licenses/SDL-webOS.txt`.

the SDK `wayland-scanner` generates the C bindings during the ARM32 build.
the app uses this protocol for the B9 keyboard. SDL's standard Wayland
text-input-v3 path did not show the keyboard on this TV.
