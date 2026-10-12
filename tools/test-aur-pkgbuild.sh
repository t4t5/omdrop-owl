#!/bin/bash
# Build the AUR's PKGBUILD (tools/aur-pkgbuild.sh) against this checkout, as CI
# does for every pull request and before a release. An archive of the working
# tree's tracked files stands in for the release tarball, which doesn't exist
# until the tag does. Arguments go to makepkg.
#
#   tools/test-aur-pkgbuild.sh [-s]
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(sed -n 's/^pkgver=//p' "$ROOT/PKGBUILD")
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

"$ROOT/tools/aur-pkgbuild.sh" "$WORK"
# A commit of the working tree when there are changes; nothing when clean.
TREE=$(git -C "$ROOT" stash create)
git -C "$ROOT" archive --prefix="omdrop-owl-$VERSION/" \
  -o "$WORK/omdrop-owl-$VERSION.tar.gz" "${TREE:-HEAD}"

# makepkg uses a source already in SRCDEST rather than downloading it.
cd "$WORK"
SRCDEST=$WORK makepkg "$@"
