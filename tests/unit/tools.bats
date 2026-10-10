#!/usr/bin/env bats
# tools/build-owl.sh and tools/stage.sh with git and cmake stubbed out: the
# pin plumbing, the patch application, the cmake flags, and the staging layout.

load ../helpers

@test "build-owl.sh configures cmake for the patched owl target" {
  [ -f /usr/include/ev.h ] || skip "libev headers not installed on this machine"
  OMDROP_UPSTREAM_ROOT="$TMP" PATH="$STUBS:$PATH" TEST_TMP="$TMP" \
    run bash "$REPO/tools/build-owl.sh"
  [ "$status" -eq 0 ]
  grep -Fq -- "-S $TMP/upstream/owl" "$TMP/cmake.log"
  grep -Fq -- "-DCMAKE_POLICY_VERSION_MINIMUM=3.5" "$TMP/cmake.log"
  grep -Fq -- "-DCMAKE_BUILD_TYPE=Release" "$TMP/cmake.log"
  grep -Fq -- "--target owl" "$TMP/cmake.log"
  [[ "$output" == *"built $TMP/upstream/owl/build/daemon/owl"* ]]
  # Every repo patch was handed to git for the pinned owl tree. build-owl.sh
  # calls `git -C <dir> apply`, so the subcommand sits mid-line; the expected
  # count comes from patches/ so adding an upstream patch needs no edit here.
  [ "$(grep -c ' apply ' "$TMP/git.log")" -eq "$(find "$REPO/patches" -name 'owl-*.patch' | wc -l)" ]
}

@test "build-owl.sh fails when a patch does not apply" {
  [ -f /usr/include/ev.h ] || skip "libev headers not installed on this machine"
  OMDROP_UPSTREAM_ROOT="$TMP" PATH="$STUBS:$PATH" TEST_TMP="$TMP" \
    TEST_GIT_APPLY_FAIL=1 \
    run bash "$REPO/tools/build-owl.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not apply"* ]]
}

@test "stage.sh assembles build/lib like /usr/lib/omdrop" {
  mkdir -p "$TMP/upstream/owl/build/daemon"
  printf '#!/bin/sh\n' > "$TMP/upstream/owl/build/daemon/owl"
  chmod +x "$TMP/upstream/owl/build/daemon/owl"
  OMDROP_STAGE_ROOT="$TMP" PATH="$STUBS:$PATH" TEST_TMP="$TMP" \
    run bash "$REPO/tools/stage.sh"
  [ "$status" -eq 0 ]
  for f in omdrop-discoverable owl \
           send-to-peer airdrop-send.py awdl-af-parse.py awdl_identity.py \
           awdl_debug.py ble-airdrop-adv.py awdl-airdrop-adv.py awdl-mdns-respond.py; do
    [ -x "$TMP/build/lib/$f" ]
  done
  [ -f "$TMP/build/lib/owl-profiles" ]   # data, not executable
  # Nothing from upstream beyond the portable tools: the radio half is ours.
  [ "$(ls "$TMP/build/lib" | wc -l)" -eq 11 ]
  [[ "$output" == *"staged $TMP/build/lib"* ]]
}
