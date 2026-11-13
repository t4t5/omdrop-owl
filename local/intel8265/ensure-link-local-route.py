#!/usr/bin/python3
"""Keep AirDrop's scoped local IPv6 replies ahead of the VPN reject rule."""

import json
import subprocess
import sys

IP = "/usr/sbin/ip"
PRIORITY = 8990
rules = json.loads(subprocess.check_output([IP, "-6", "-j", "rule", "show"]))
expected = {
    "priority": PRIORITY,
    "src": "all",
    "dst": "fe80::",
    "dstlen": 64,
    "oif": "awdl0",
    "table": "main",
}
if any(all(rule.get(key) == value for key, value in expected.items()) for rule in rules):
    sys.exit(0)
if any(rule.get("priority") == PRIORITY for rule in rules):
    sys.exit(f"IPv6 rule priority {PRIORITY} is already in use; existing rules were preserved.")
subprocess.run(
    [IP, "-6", "rule", "add", "priority", str(PRIORITY),
     "to", "fe80::/64", "oif", "awdl0", "lookup", "main"],
    check=True,
)
