#!/bin/bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$ROOT/build"
cc -O2 -Wall -Wextra -Werror "$ROOT/native/awdl-go.c" \
  $(pkg-config --cflags --libs libnl-3.0 libnl-genl-3.0) -o "$ROOT/build/awdl-go"
"$ROOT/build/awdl-go" --self-test
