#!/bin/bash
# Build an .rpm of omdrop-owl for Fedora, the counterpart of PKGBUILD and
# tools/build-deb.sh: the same files at the same paths. Builds OWL and stages
# build/lib with tools/build-owl.sh and tools/stage.sh, writes a spec into a
# throwaway tree, and packs it with rpmbuild. Needs no root or source tarball.
# (The Requires use Fedora package names; other rpm distros would rename them.)
#
#   sudo dnf install rpm-build cmake gcc make git libev-devel libpcap-devel libnl3-devel
#   tools/build-rpm.sh
#   sudo dnf install ./omdrop-owl-*.rpm
set -eu
umask 022

ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIB=$ROOT/build/lib
UP=$ROOT/upstream
PKG=omdrop-owl
VERSION=$(sed -n 's/^pkgver=//p' "$ROOT/PKGBUILD")
RELEASE=$(sed -n 's/^pkgrel=//p' "$ROOT/PKGBUILD")
ARCH=$(uname -m)
# PKGBUILD's depends, by their Fedora names (mirrors build-deb.sh's Debian
# names). The shared libraries OWL links (libev, libnl3, libpcap) are added by
# rpmbuild's automatic dependency generation, as dpkg-shlibdeps does for deb.
REQUIRES="bash python3 iproute iputils iw polkit util-linux procps-ng
 NetworkManager keyutils python3-libarchive-c python3-pillow python3-zeroconf
 python3-ifaddr bluez python3-dbus python3-gobject"
# One space-separated line for the spec's Requires:.
REQ=$(echo $REQUIRES)

"$ROOT/tools/build-owl.sh"
"$ROOT/tools/stage.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
TOP=$WORK/top
mkdir -p "$TOP"/{BUILD,RPMS,SRPMS,SPECS,SOURCES,payload}
PAYLOAD=$TOP/payload

install -d "$PAYLOAD/usr/lib/omdrop"
# Files only: running the tools as root leaves a root-owned __pycache__ in
# build/lib, which isn't ours to ship.
find "$LIB" -maxdepth 1 -type f -exec install -m755 -t "$PAYLOAD/usr/lib/omdrop" {} +
chmod 644 "$PAYLOAD/usr/lib/omdrop/owl-profiles"
install -Dm644 "$ROOT/packaging/omdrop-owl.policy" \
  "$PAYLOAD/usr/share/polkit-1/actions/io.github.t4t5.omdrop-owl.policy"
install -Dm644 "$ROOT/packaging/99-omdrop-owl-unmanaged.conf" \
  "$PAYLOAD/usr/lib/NetworkManager/conf.d/99-omdrop-owl-unmanaged.conf"
LIC=$PAYLOAD/usr/share/licenses/$PKG
install -Dm644 "$UP/owl/COPYING" "$LIC/OWL-GPL-3.0"
install -Dm644 "$UP/omdrop-awdl/LICENSE" "$LIC/omdrop-awdl-LICENSE"
install -Dm644 "$UP/owl/radiotap/COPYING" "$LIC/radiotap-ISC"
install -Dm644 "$ROOT/README.md" "$PAYLOAD/usr/share/doc/$PKG/README.md"

# Maintainer scripts mirror packaging/deb/postinst and prerm: reload
# NetworkManager's conf.d after install, and don't leave a window running on
# removal. The prebuilt payload is copied into the build root in %install, the
# way a spec normally assembles it; debuginfo and the brp rewrites (strip,
# python bytecompile, shebang mangling) are switched off.
cat > "$TOP/SPECS/$PKG.spec" <<EOF
Name: $PKG
Version: $VERSION
Release: $RELEASE
Summary: AirDrop radio backend for omdrop on MediaTek MT7925 Wi-Fi
License: GPL-3.0-or-later AND GPL-2.0-only AND ISC
URL: https://github.com/t4t5/omdrop-owl
BuildArch: $ARCH
Requires: $REQ
Conflicts: brcmfmac-awdl-dkms

%global payload $PAYLOAD
%global debug_package %{nil}
%global __os_install_post %{nil}
%global _build_id_links none

%description
AirDrop radio backend for omdrop on MediaTek MT7925 Wi-Fi: AWDL runs in
userspace through OWL on a monitor interface, so AirDrop works without Apple's
Broadcom firmware while Wi-Fi stays connected. Installs helpers into
/usr/lib/omdrop for omdrop's CLI and panel to call.

%prep
:
%build
:
%install
mkdir -p %{buildroot}
cp -a %{payload}/. %{buildroot}/

%files
/usr/lib/omdrop
/usr/share/polkit-1/actions/io.github.t4t5.omdrop-owl.policy
/usr/lib/NetworkManager/conf.d/99-omdrop-owl-unmanaged.conf
/usr/share/licenses/$PKG
/usr/share/doc/$PKG

%post
if systemctl is-active --quiet NetworkManager 2>/dev/null; then
  nmcli general reload conf >/dev/null 2>&1 || \\
    echo "  Could not reload NetworkManager's configuration. Run: sudo nmcli general reload conf"
fi
cat <<'MSG'
  omdrop-owl is omdrop's radio half for Wi-Fi cards without Apple's Broadcom
  firmware. Nothing runs until omdrop asks. Install omdrop itself, in a version
  that supports radio backends (docs/radio-backend.md), and turn it on there.

  Your Wi-Fi access point has to be on channel 6, 44 or 149: AirDrop shares
  its channel. \`/usr/lib/omdrop/omdrop-discoverable probe\` says what, if
  anything, is in the way.
MSG

%preun
/usr/lib/omdrop/omdrop-discoverable stop >/dev/null 2>&1 || true

%changelog
* Sat Oct 10 2026 omdrop-owl <https://github.com/t4t5/omdrop-owl> - $VERSION-$RELEASE
- Initial rpm package, mirroring tools/build-deb.sh.
EOF

rpmbuild -bb --define "_topdir $TOP" "$TOP/SPECS/$PKG.spec" >/dev/null
OUT=$ROOT/${PKG}-${VERSION}-${RELEASE}.${ARCH}.rpm
cp "$TOP/RPMS/$ARCH/${PKG}-${VERSION}-${RELEASE}.${ARCH}.rpm" "$OUT"
echo "built $OUT"
