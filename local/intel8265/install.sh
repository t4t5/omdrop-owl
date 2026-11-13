#!/bin/sh
# Install the local daemon alongside the distribution package, preserving it.
set -eu

TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TASK_DAEMON="$TASK_ROOT/target/release/owlyd"
TASK_CONFIG=/etc/owly/radio.toml
TASK_DROPIN=/etc/systemd/system/owlyd.service.d/8265-workaround.conf
TASK_DEST=/usr/local/lib/owly-8265/owlyd

case "${1:-}" in
    ''|--check) ;;
    *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac
[ -x "$TASK_DAEMON" ] || { echo "Build owlyd in release mode first." >&2; exit 1; }

# Do not replace a machine's existing radio settings. The current machine
# has no settings file; an existing one must already opt into this experiment.
python3 - "$TASK_CONFIG" <<'PY'
import pathlib, sys, tomllib
path = pathlib.Path(sys.argv[1])
if path.exists():
    with path.open('rb') as stream:
        config = tomllib.load(stream)
    if config.get('allow_untested') is not True:
        sys.exit(f'Set allow_untested = true in {path}, preserving its other settings, then retry.')
PY

if [ "${1:-}" = --check ]; then
    echo "Ready: install the patched daemon at $TASK_DEST"
    echo "Set owlyd's ExecStart through $TASK_DROPIN"
    echo "Enable experimental hardware in $TASK_CONFIG and restart owlyd."
    exit 0
fi
[ "$(id -u)" -eq 0 ] || { echo "Run: sudo sh $0" >&2; exit 1; }

TASK_BACKUP="/var/backups/owly-8265-$(date -u +%Y%m%dT%H%M%SZ)-$$"
install -d -m 0755 "$TASK_BACKUP"
for TASK_EXISTING in "$TASK_CONFIG" "$TASK_DROPIN" "$TASK_DEST"; do
    if [ -f "$TASK_EXISTING" ]; then
        cp -p -- "$TASK_EXISTING" "$TASK_BACKUP/$(basename -- "$TASK_EXISTING")"
    fi
done
install -D -m 0755 "$TASK_DAEMON" "$TASK_DEST"
if [ ! -e "$TASK_CONFIG" ]; then
    install -d -m 0755 /etc/owly
    printf '%s\n' '# Local Intel 8265 firmware workaround (PR #117).' 'allow_untested = true' > "$TASK_CONFIG"
    chmod 0644 "$TASK_CONFIG"
fi
install -d -m 0755 /etc/systemd/system/owlyd.service.d
printf '%s\n' '[Service]' 'ExecStart=' "ExecStart=$TASK_DEST" > "$TASK_DROPIN"
chmod 0644 "$TASK_DROPIN"
systemctl daemon-reload
systemctl restart owlyd
systemctl is-active --quiet owlyd
echo "Patched service running. Previous local files saved in $TASK_BACKUP"
/usr/bin/owly doctor
