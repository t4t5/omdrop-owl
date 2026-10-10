#!/usr/bin/env bats
# Packaging sanity across the three package formats: the PKGBUILD, the
# Debian/Ubuntu packer (tools/build-deb.sh) and the Fedora/rpm packer
# (tools/build-rpm.sh) must stay in step. All static parsing, so drift is
# caught before anything is built.

load ../helpers

DEB=$REPO/tools/build-deb.sh
RPM=$REPO/tools/build-rpm.sh

@test "PKGBUILD's pinned commits match pins" {
  [ "$(sed -n 's/^_owl_commit=//p' "$REPO/PKGBUILD")" = "$(sed -n 's/^OWL_COMMIT=//p' "$REPO/pins")" ]
  [ "$(sed -n 's/^_omdrop_awdl_commit=//p' "$REPO/PKGBUILD")" = "$(sed -n 's/^OMDROP_AWDL_COMMIT=//p' "$REPO/pins")" ]
}

@test "the helper's VERSION matches the PKGBUILD pkgver" {
  [ "$(sed -n 's/^pkgver=//p' "$REPO/PKGBUILD")" = "$(sed -n 's/^VERSION=//p' "$REPO/userspace/omdrop-discoverable")" ]
}

@test "both binary packers derive their version from the PKGBUILD and stage build/lib" {
  for f in "$DEB" "$RPM"; do
    grep -q "s/^pkgver=//p" "$f"
    grep -q 'tools/build-owl.sh' "$f"
    grep -q 'tools/stage.sh' "$f"
  done
}

@test "both packers install the same three non-helper paths as package()" {
  for path in \
    '/usr/lib/omdrop' \
    '/usr/share/polkit-1/actions/io.github.t4t5.omdrop-owl.policy' \
    '/usr/lib/NetworkManager/conf.d/99-omdrop-owl-unmanaged.conf'; do
    grep -qF "$path" "$DEB" || fail "build-deb.sh is missing $path"
    grep -qF "$path" "$RPM" || fail "build-rpm.sh is missing $path"
    grep -qF "$path" "$REPO/PKGBUILD" || fail "PKGBUILD is missing $path"
  done
}

@test "both packers ship all three licenses and conflict with the Broadcom backend" {
  for f in OWL-GPL-3.0 omdrop-awdl-LICENSE radiotap-ISC; do
    grep -qF "$f" "$DEB" || fail "build-deb.sh is missing license $f"
    grep -qF "$f" "$RPM" || fail "build-rpm.sh is missing license $f"
  done
  grep -q 'brcmfmac-awdl-dkms' "$DEB"
  grep -q 'brcmfmac-awdl-dkms' "$RPM"
  grep -q 'conflicts=.*brcmfmac-awdl-dkms' "$REPO/PKGBUILD"
}

@test "the rpm packer packs a prebuilt tree, not a source build" {
  # Mirrors build-deb.sh: a pre-staged tree, no %setup/%build or brp rewrites.
  grep -q '__os_install_post' "$RPM"
  ! grep -Eq '%setup|%autosetup|%configure|%cmake ' "$RPM"
}

@test "tests run in CI, not at package build time" {
  grep -q 'tools/run-tests.sh' "$REPO/.github/workflows/ci.yml"
  ! grep -q 'run-tests.sh' "$REPO/PKGBUILD"
}
