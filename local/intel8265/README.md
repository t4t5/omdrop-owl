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

To select the packaged daemon again, edit the drop-in so its last line reads
`ExecStart=/usr/lib/owly/owlyd`, then run `sudo systemctl daemon-reload` and
`sudo systemctl restart owlyd`. To restore experimental hardware blocking,
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
successful transfer on this card. The published results use an iPhone;
Mac interoperability still needs a real transfer test.

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
