# Local Intel Wireless-AC 8265 workaround

This branch backports [Owly PR #117](https://github.com/t4t5/owly/pull/117)
(commit `cfb06ec73e22f24bf47468d259f18c835bc5470d`) onto Owly 0.4.3.
The original findings and iPhone transfer results are in
[issue #116](https://github.com/t4t5/owly/issues/116).

The workaround sends broadcast/multicast frames as individual unicast copies
to known peers and rejoins the ad-hoc cell every nine seconds. Both behaviors
apply only to PCI device `8086:24fd`. Other cards retain their defaults. The
card remains marked experimental and requires `allow_untested = true`.
Local additions validate the rejoin interval, reject group addresses when
choosing unicast recipients, and test device selection, periodic rejoining,
preservation of the AWDL interface, spoofed peers, and shutdown recovery.

## Install

From this checkout:

```sh
cargo build --release --locked -p owlyd -p owly-cli
sh local/intel8265/install.sh --check
sudo sh local/intel8265/install.sh
```

The installer keeps the packaged `/usr/lib/owly/owlyd` and `/usr/bin/owly`.
It installs the patched daemon at `/usr/local/lib/owly-8265/owlyd` and uses
`/etc/systemd/system/owlyd.service.d/8265-workaround.conf` to select it.
Any existing local daemon, drop-in, or configuration is copied to a new
directory under `/var/backups/owly-8265-*` before installation. An existing
radio configuration must already contain `allow_untested = true`; the script
will stop instead of replacing other settings.

This machine also has a VPN rule at IPv6 priority 9000 that rejects traffic
before the main routing table. Packet capture showed the Mac's TCP SYNs
arriving on port 8771 without a reply. A rule at priority 8990 now selects
the main table only for `fe80::/64` traffic explicitly scoped to `awdl0`.
The service's `ExecStartPre` helper ensures this rule exists after a reboot.
It preserves other rules and refuses to use an occupied priority. The rule
stays detached while `awdl0` is absent, and affects neither global IPv6
destinations nor other output interfaces.

To select the packaged daemon again, edit the drop-in so its last line reads
`ExecStart=/usr/lib/owly/owlyd`, then run `sudo systemctl daemon-reload` and
`sudo systemctl restart owlyd`. Omit the local `ExecStartPre` line to stop
recreating the scoped routing exception at service startup. To restore experimental hardware blocking,
set `allow_untested = false` in `/etc/owly/radio.toml`.

## Receive from a Mac

Keep this running in one terminal:

```sh
owly radio up
```

In a second terminal:

```sh
owly receive --name "Moein Linux" --dir ~/Downloads
```

On the Mac, turn on Wi-Fi and Bluetooth, then select a small test file in
Finder and use Share > AirDrop. Select Moein Linux if it appears, then accept
the request in the receiving terminal. Stop both commands with Ctrl+C.

The laptop's normal Wi-Fi disconnects while the radio is running. The firmware
restart causes approximately one second of interruption every ten seconds;
large transfers can need a retry. A passing simulation is not proof of a
successful transfer on this card. The published hardware results use an iPhone.
On this machine, a MacBook Pro running macOS 27.0.1 successfully completed
discovery and offered CHANGELOG.md after the routing exception was added.
Completed file reception still needs confirmation.

For a bounded test in a local terminal (including an interactive acceptance
prompt), run `bash local/intel8265/receive-test.sh`. It waits for the radio's
D-Bus session before starting discovery and keeps `timeout` in the foreground
so terminal input can reach the receiver.

## Validation on this machine

- The group-to-unicast regression failed before the backport and passed after it.
- The spoofed-peer regression aborted the unguarded driver and passed with the guard.
- `cargo test --locked -p owly-awdl --features driver`: 63 passed.
- `cargo test --locked -p owly-radio --lib --test injection`: 55 passed.
- `cargo test --locked -p owlyd --test service`: 11 passed.
- Workspace library/binary tests, formatting, Clippy, hardware table consistency,
  and protocol coverage checks passed. The release binaries built successfully.
- The native kernel integration test cannot run under this machine's current
  user-namespace restrictions (`unshare: ... uid_map: Operation not permitted`).
  The host security policy was left unchanged.
- `local/intel8265/test-routing.sh` passed in isolated network namespaces:
  the exception allows scoped AirDrop replies, preserves blocking for global
  IPv6 and other interfaces, is idempotent, and refuses an occupied priority
  without changing existing rules.
