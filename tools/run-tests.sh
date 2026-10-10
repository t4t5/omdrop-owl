#!/bin/bash
# Run the unit tests (bats). The single entry point for CI and developers:
#   tools/run-tests.sh              everything in tests/unit
#   tools/run-tests.sh <file.bats>  one file
# Deliberately not wired into PKGBUILD check() or the RPM %check: these run at
# development and CI time, not at package build time.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
command -v bats >/dev/null || { echo "bats is not installed (pacman -S bats / dnf install bats / apt install bats)"; exit 1; }
cd "$ROOT"
exec bats tests/unit "$@"
