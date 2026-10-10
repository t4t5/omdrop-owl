#!/usr/bin/env bats
# The owl-profiles table format: what load_profile parses, and the invariants
# the README promises (a "*" fallback that needs opt-in).

load ../helpers

validate_table() {  # FILE -> awk exits nonzero on any violation
  awk '
    /^#/ || !NF { next }
    {
      bad = 0
      if (NF < 6) bad = 1
      if ($2 != "tested" && $2 != "untested") bad = 1
      if ($3 != "shared" && $3 != "exclusive") bad = 1
      if ($4 != "station" && $4 != "own") bad = 1
      if ($5 != "yes" && $5 != "no") bad = 1
      if ($6 != "yes" && $6 != "no") bad = 1
      if (bad) { printf "%s:%d: bad row: %s\n", FILENAME, NR, $0; n++ }
      if ($1 == "*") fallback++
      drivers[$1]++
    }
    END {
      if (fallback != 1) { printf "%s: need exactly one \"*\" fallback row, found %d\n", FILENAME, fallback; n++ }
      for (d in drivers)
        if (drivers[d] > 1) { printf "%s: duplicate driver %s\n", FILENAME, d; n++ }
      if (n) exit 1
      exit 0
    }' "$1"
}

@test "the packaged owl-profiles table is well-formed" {
  run validate_table "$REPO/userspace/owl-profiles"
  [ "$status" -eq 0 ]
}

@test "the packaged fallback row is untested" {
  run awk '$1 == "*" && !/^#/ { print $2 }' "$REPO/userspace/owl-profiles"
  [ "$status" -eq 0 ]
  [ "$output" = untested ]
}

@test "the packaged table documents the mt7925e as tested" {
  run awk '$1 == "mt7925e" && !/^#/ { print $2 }' "$REPO/userspace/owl-profiles"
  [ "$output" = tested ]
}

@test "the test fixture is well-formed" {
  run validate_table "$REPO/tests/fixtures/owl-profiles"
  [ "$status" -eq 0 ]
}

@test "the validator catches a bad row" {
  printf 'r8168 broken shared station yes no bad row\n' > "$TMP/bad"
  run validate_table "$TMP/bad"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bad row"* ]]
}

@test "the validator catches a missing fallback" {
  printf 'mt7925e tested shared station yes no MediaTek\n' > "$TMP/nofallback"
  run validate_table "$TMP/nofallback"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fallback"* ]]
}

@test "the validator catches duplicate drivers" {
  {
    printf 'mt7925e tested shared station yes no MediaTek\n'
    printf 'mt7925e tested shared own no no MediaTek again\n'
    printf '* untested shared station yes no other\n'
  } > "$TMP/dup"
  run validate_table "$TMP/dup"
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate"* ]]
}
