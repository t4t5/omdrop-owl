# Shared by the unit tests: the repo root, a scratch dir per test, and `fail`.

# shellcheck disable=SC2034  # used by the .bats files that load this
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# This bats build does not ship `fail`; provide the usual semantics.
fail() { echo "$*" >&2; exit 1; }

setup() {
  TMP=$(mktemp -d "${TMPDIR:-/tmp}/omdrop-owl-test.XXXXXX")
}

teardown() {
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
  return 0
}
