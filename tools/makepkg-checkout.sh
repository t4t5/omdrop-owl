#!/bin/bash
# Run makepkg on this checkout, uncommitted changes to tracked files included,
# instead of the tagged release PKGBUILD downloads: makepkg uses a source
# that's already in SRCDEST rather than fetching it. Arguments go to makepkg.
#
#   tools/makepkg-checkout.sh -si
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
VERSION=$(sed -n 's/^pkgver=//p' PKGBUILD)
TARBALL=omdrop-owl-$VERSION.tar.gz

trap 'rm -f "$ROOT/$TARBALL"' EXIT
# A commit of the working tree when there are changes; nothing when clean.
TREE=$(git stash create)
git archive --prefix="omdrop-owl-$VERSION/" -o "$TARBALL" "${TREE:-HEAD}"

# -C: start from an empty src/, so a file deleted here isn't left in the last
# extraction (a removed patch would still be applied).
SRCDEST=$ROOT makepkg -C "$@"
