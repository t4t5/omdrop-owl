#!/bin/bash
# Check a built .rpm against the PKGBUILD: the same files at the same paths
# with the same modes, and the same conflicts. The expected list comes from
# running PKGBUILD's package() with `install` recorded instead of run, so a
# file added there and not to the rpm (or the other way) fails here.
#
#   tools/build-rpm.sh && tools/check-rpm.sh omdrop-owl-*.rpm
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
RPM=${1:?usage: tools/check-rpm.sh FILE.rpm}

expected=$(
  # shellcheck disable=SC1091
  . "$ROOT/PKGBUILD"
  install() {  # install -Dm<mode> SRC DEST, as package() calls it
    case "$1" in -Dm[0-7][0-7][0-7]) ;; *) echo "check-rpm.sh doesn't know install $*" >&2; exit 1 ;; esac
    echo "${1#-Dm} ${!#}"
  }
  # shellcheck disable=SC2034  # read by package()
  pkgdir='' startdir=$ROOT
  package
)
# Regular files only (octal mode 100xxx): rpm also lists the directories.
actual=$(rpm -qp --qf '[%{FILEMODES:octal} %{FILENAMES}\n]' "$RPM" | sed -n 's/^100\([0-7]\{3\}\) /\1 /p')
if ! diff -u <(sort <<< "$expected") <(sort <<< "$actual") --label PKGBUILD --label "$(basename "$RPM")"; then
  echo "$(basename "$RPM") doesn't install what PKGBUILD's package() does"
  exit 1
fi

conflicts=$(. "$ROOT/PKGBUILD"; printf '%s\n' "${conflicts[@]}")
for c in $conflicts; do
  rpm -qp --conflicts "$RPM" | grep -qx "$c" || { echo "$(basename "$RPM") doesn't conflict with $c"; exit 1; }
done

echo "$(basename "$RPM"): $(wc -l <<< "$actual") files, as PKGBUILD installs them"
