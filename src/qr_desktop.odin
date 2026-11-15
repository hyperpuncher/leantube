#+build linux:default amd64, linux:default arm64
package main

@(export)
foreign import qr "../build/host-qr/qrcodegen.a"
