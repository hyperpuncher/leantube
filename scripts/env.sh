#!/usr/bin/env bash
# Sourced by project scripts. Run them from the project root through just.
: "${WEBOS_TOOLCHAIN:=$PWD/.cache/toolchain}"
WEBOS_TOOLCHAIN=$(realpath -m "$WEBOS_TOOLCHAIN")
export WEBOS_TOOLCHAIN
export WEBOS_SDK="$WEBOS_TOOLCHAIN/sdk"
export WEBOS_ODIN="$WEBOS_TOOLCHAIN/odin/odin"
export WEBOS_PLATFORM="$WEBOS_TOOLCHAIN/platform"
app_id=$(jq -r .id app/appinfo.json)
app_main=$(jq -r .main app/appinfo.json)
app_version=$(jq -r .version app/appinfo.json)
app_dir="/media/developer/apps/usr/palm/applications/$app_id"
export app_id app_main app_version app_dir
