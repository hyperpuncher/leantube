package main

// The ARM32 build links qrcodegen.c with the Odin object.
@(export)
foreign import qr "system:qrcodegen"
