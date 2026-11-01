# webOS SDK installation

LeanTube pins `@webos-tools/cli` 3.2.6 as a development dependency and runs its
commands from `node_modules/.bin`. the CLI still uses the existing global device
settings, including the default `tv-ssh` device. the global SDK is not changed.

`patches/@webos-tools%2Fcli@3.2.6.patch` is applied by `bun install`. it makes
SDK uploads use the existing stream transfer unless a device sets `files` to
`sftp`. on the tested TV, an SFTP upload succeeds, but the next command on the
same SSH connection fails with `Unable to exec`. stream transfer works. this
changes only how the installer sends its temporary IPK; no TV setting or system
library changes.

run `bun install` after changing the CLI version. update the patch when a newer
CLI already uses stream transfer, then remove the dependency pin and patch.
