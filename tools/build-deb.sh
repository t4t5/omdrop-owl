#!/bin/bash
# Build a .deb of omdrop-owl for Debian and Ubuntu, the counterpart of
# PKGBUILD: the same files at the same paths. Builds OWL and stages build/lib
# with tools/build-owl.sh and tools/stage.sh, then packs it with dpkg-deb.
# Needs no root.
#
#   sudo apt install build-essential cmake git pkg-config dpkg-dev \
#     libev-dev libpcap-dev libnl-3-dev libnl-genl-3-dev
#   tools/build-deb.sh
#   sudo apt install ./omdrop-owl_*.deb
set -eu
umask 022

ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIB=$ROOT/build/lib
UP=$ROOT/upstream
PKG=omdrop-owl
VERSION=$(sed -n 's/^pkgver=//p' "$ROOT/PKGBUILD")-$(sed -n 's/^pkgrel=//p' "$ROOT/PKGBUILD")
ARCH=$(dpkg --print-architecture)
# PKGBUILD's depends, by their Debian names. The shared libraries OWL links
# against are added by dpkg-shlibdeps.
DEPENDS="bash, python3, iproute2, iputils-ping, iw, pkexec, polkitd, util-linux, procps,
 network-manager, keyutils, python3-libarchive-c, python3-pil, python3-zeroconf,
 python3-ifaddr, bluez, python3-dbus, python3-gi"

"$ROOT/tools/build-owl.sh"
"$ROOT/tools/stage.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
D=$WORK/root

# Files only: running the tools as root leaves a root-owned __pycache__ in
# build/lib, which isn't ours to ship.
install -d "$D/usr/lib/omdrop"
find "$LIB" -maxdepth 1 -type f -exec install -m755 -t "$D/usr/lib/omdrop" {} +
chmod 644 "$D/usr/lib/omdrop/owl-profiles"
install -Dm644 "$ROOT/packaging/omdrop-owl.policy" \
  "$D/usr/share/polkit-1/actions/io.github.t4t5.omdrop-owl.policy"
install -Dm644 "$ROOT/packaging/99-omdrop-owl-unmanaged.conf" \
  "$D/usr/lib/NetworkManager/conf.d/99-omdrop-owl-unmanaged.conf"
DOC=$D/usr/share/doc/$PKG
install -Dm644 "$ROOT/README.md" "$DOC/README.md"
install -Dm644 "$UP/owl/COPYING" "$DOC/OWL-GPL-3.0"
install -Dm644 "$UP/omdrop-awdl/LICENSE" "$DOC/omdrop-awdl-LICENSE"
install -Dm644 "$UP/owl/radiotap/COPYING" "$DOC/radiotap-ISC"
cat > "$DOC/copyright" <<'EOF'
omdrop-owl ships separate programs under separate licenses:

  omdrop-discoverable, owl-profiles, and the patches to OWL: GPL-3.0-or-later
  owl (OWL, https://github.com/jedbillyb/owl): GPL-3.0-or-later (OWL-GPL-3.0)
  OWL's bundled radiotap parser: ISC (radiotap-ISC)
  omdrop-awdl's tools (send-to-peer, *.py): GPL-2.0-only (omdrop-awdl-LICENSE)
EOF

# dpkg-shlibdeps wants a debian/control to read; it only needs the source
# stanza.
mkdir -p "$WORK/debian"
printf 'Source: %s\n\nPackage: %s\nArchitecture: any\n' "$PKG" "$PKG" > "$WORK/debian/control"
SHLIBS=$(cd "$WORK" && dpkg-shlibdeps -O "$D/usr/lib/omdrop/owl" 2>/dev/null | sed -n 's/^shlibs:Depends=//p')

install -d "$D/DEBIAN"
install -m755 "$ROOT/packaging/deb/postinst" "$ROOT/packaging/deb/prerm" "$D/DEBIAN/"
cat > "$D/DEBIAN/control" <<EOF
Package: $PKG
Version: $VERSION
Architecture: $ARCH
Maintainer: omdrop-owl <https://github.com/t4t5/omdrop-owl>
Installed-Size: $(du -sk "$D" | cut -f1)
Depends: ${SHLIBS:+$SHLIBS, }$(echo $DEPENDS)
Conflicts: brcmfmac-awdl-dkms
Section: net
Priority: optional
Homepage: https://github.com/t4t5/omdrop-owl
Description: AirDrop radio backend for omdrop: AWDL in userspace through OWL
 The radio half of omdrop for machines without Apple's Broadcom Wi-Fi. AWDL
 runs in userspace through OWL on a monitor interface, sharing the channel of
 the connected access point, and omdrop's receiver and sender run over it.
EOF

OUT=$ROOT/${PKG}_${VERSION}_${ARCH}.deb
dpkg-deb --root-owner-group -Zxz --build "$D" "$OUT" >/dev/null
echo "built $OUT"
