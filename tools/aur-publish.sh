#!/bin/bash
# Publish PKGBUILD to the AUR with the release tarball's checksum filled in.
# .github/workflows/release.yml runs this once v<pkgver> is tagged. KEY is an
# SSH key registered with an AUR account that maintains omdrop-owl; without
# one, ssh uses its defaults. Does nothing if the AUR already has this.
#
#   tools/aur-publish.sh [KEY]
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
KEY=${1:-}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The AUR's Ed25519 host key, whose fingerprint
# (SHA256:RFzBCUItH9LZS0cKB5UE6ceAYhBD5C8GeOBip8Z11+4) is the one published on
# aur.archlinux.org.
echo 'aur.archlinux.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEuBKrPzbawxA/k2g6NcyV5jmqwJ2s+zpgZGZ7tpLIcN' \
  > "$WORK/known_hosts"
GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=$WORK/known_hosts -o StrictHostKeyChecking=yes"
[[ -n "$KEY" ]] && GIT_SSH_COMMAND+=" -i $KEY -o IdentitiesOnly=yes"
export GIT_SSH_COMMAND

# Cloning a package that doesn't exist yet gives an empty repository, and the
# first push creates it.
git clone --quiet ssh://aur@aur.archlinux.org/omdrop-owl.git "$WORK/aur"
cp "$ROOT/PKGBUILD" "$ROOT/omdrop-owl.install" "$WORK/aur/"
cd "$WORK/aur"

# Into an empty SRCDEST, so a local tarball can't stand in for the published
# one. This also sums the git sources pinned to a commit; the others stay SKIP.
SRCDEST=$WORK/src updpkgsums
makepkg --printsrcinfo > .SRCINFO

git add PKGBUILD .SRCINFO omdrop-owl.install
if git diff --cached --quiet; then
  echo "The AUR already has this PKGBUILD."
  exit 0
fi
VERSION=$(sed -n 's/^pkgver=//p' PKGBUILD)-$(sed -n 's/^pkgrel=//p' PKGBUILD)
git commit --quiet -m "Update to $VERSION"
# The AUR only takes master.
git push --quiet origin HEAD:master
echo "Published omdrop-owl $VERSION to the AUR."
