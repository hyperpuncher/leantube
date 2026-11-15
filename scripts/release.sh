#!/usr/bin/env bash
# Bump the app version, commit, and tag. Pushing the tag publishes the release.
set -euo pipefail

part=${1:-}
if [[ $part != patch && $part != minor && $part != major ]]; then
	printf 'usage: just release patch|minor|major\n' >&2
	exit 2
fi
if [[ $(git branch --show-current) != main ]]; then
	printf 'release from main only\n' >&2
	exit 1
fi
if [[ -n $(git status --porcelain) ]]; then
	printf 'commit or stash changes first\n' >&2
	exit 1
fi

current=$(jq -r .version app/appinfo.json)
IFS=. read -r major minor patch <<<"$current"
case $part in
patch) patch=$((patch + 1)) ;;
minor) minor=$((minor + 1)) patch=0 ;;
major) major=$((major + 1)) minor=0 patch=0 ;;
esac
version=$major.$minor.$patch
if git rev-parse -q --verify "refs/tags/v$version" >/dev/null; then
	printf 'tag v%s already exists\n' "$version" >&2
	exit 1
fi

just check
just test

info=$(jq --tab --arg version "$version" '.version = $version' app/appinfo.json)
printf '%s\n' "$info" >app/appinfo.json
git commit -q -m "chore: release v$version" app/appinfo.json
git tag -a "v$version" -m "v$version"
printf 'v%s -> v%s tagged. publish with:\n  git push origin main v%s\n' "$current" "$version" "$version"
