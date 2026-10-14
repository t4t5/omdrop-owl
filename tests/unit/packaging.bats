#!/usr/bin/env bats
# The version and pins the PKGBUILD shares with the rest of the tree. What the
# packages install is checked on the built rpm (tools/check-rpm.sh, in CI).

load ../helpers

@test "PKGBUILD's pinned commits match pins" {
  [ "$(sed -n 's/^_owl_commit=//p' "$REPO/PKGBUILD")" = "$(sed -n 's/^OWL_COMMIT=//p' "$REPO/pins")" ]
  [ "$(sed -n 's/^_omdrop_awdl_commit=//p' "$REPO/PKGBUILD")" = "$(sed -n 's/^OMDROP_AWDL_COMMIT=//p' "$REPO/pins")" ]
}

@test "the helper's VERSION matches the PKGBUILD pkgver" {
  [ "$(sed -n 's/^pkgver=//p' "$REPO/PKGBUILD")" = "$(sed -n 's/^VERSION=//p' "$REPO/userspace/omdrop-discoverable")" ]
}
