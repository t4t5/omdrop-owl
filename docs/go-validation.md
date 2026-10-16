# P2P-GO transmit-anchor validation

The original local implementation was tested on one MediaTek MT7922
(`14c3:0616`, `mt7921e`), x86_64 Omarchy, kernel `7.2.5-3-omarchy`.
The card did not advertise IBSS support; exclusive mode failed with
`Operation not supported (-95)`. Monitor-only experiments received Apple
traffic but did not reliably complete connections.

A temporary P2P-GO group created by stock `wpa_supplicant` on channel 6 supplied
the transmit channel. Passive and active monitors used the group MAC;
OWL used the active monitor with `-N -S intersect -F -E`. The mechanism follows
[jedbillyb's MT7921 research](https://github.com/jedbillyb/mt7921-dual-channel).

## Observed on the original implementation

- Mac to Linux: approximately 6.24 MB at 0.20 MB/s with a temporary receiver.
- The installed Omdrop receiver completed repeated transfers, including an
  approximately 1.2 MB HEIC upload with HTTP 200.
- Linux to Mac: a 32-byte text file, with successful Discover, Ask and Upload.
- The user confirmed iPhone-to-Linux receiving and normal panel operation.
- A 15-second window expired, removed the group and both monitors, terminated
  the owned supplicant and restored NetworkManager control. Ethernet stayed up.
- Closing descriptor 9 and redirecting supplicant output prevented its daemon
  from holding the helper's lock and delaying startup/stop.

Normal Wi-Fi on the same radio was not tested concurrently. The mode dedicates
that radio to AirDrop during the window. Apple OS versions were not collected.

## This contribution

The contribution is rebased on main after #24. It exposes a generic, opt-in
`go` profile rather than changing `mt7921e`'s packaged default. Group selection
uses the phy and interface type, not a MediaTek-specific interface name. It
reuses main's exclusive teardown and connection recovery. The example override
is `mt7921e untested go station no yes`, with the existing allow-untested gate.

The earlier local Apple-action padding patch is deliberately absent: main
already includes the padding fix from #7. No parser changes are proposed here.

Command-double tests exercise startup, the monitor MACs and OWL arguments,
generic profile selection, startup failures, teardown/expiry cleanup, foreign
radio groups, and stale PIDs without touching the radio. These do not replace
live validation of this rebased implementation or establish support for other
cards. The installed working receiver was left unchanged while preparing it.

No captures, certificates, contact identifiers, private network addresses,
device hostnames, received files or account paths are included.

## Fresh installed-branch check, 2026-10-14

Commit `42b2ac5` was built through `makepkg` and installed as
`omdrop-owl 0.1.1-1`, replacing the original local package. The override was
changed from `p2p` to `go`; existing receiver settings were preserved.

- The normal receiver completed Mac-to-Linux Discover, Ask and Upload with
  HTTP 200, storing a 463,586-byte HEIC file. Filesystem size was verified and
  the user confirmed completion on the Mac.
- Contacts Only remained enabled; the receiver accepted a known contact.
- Visibility was delayed by over a minute after startup. This test does not
  establish immediate discovery or isolate the reason for that delay.
- Normal `omdrop off` removed the temporary radio interfaces and returned the
  Wi-Fi station to NetworkManager.
- A new 15-second radio-only window expired with reason `expired`, removing
  the GO group, mon0/mon1, control directory and recorded state. No owned
  supplicant remained; the station was managed/disconnected and Ethernet
  stayed connected. The receive service remained stopped for this check.
- `pacman -Qkk` reported zero altered package files, and the installed helper
  byte-matched the tested commit.

Linux-to-Mac sending and iPhone receiving have not been re-tested on this
rebased installed branch; their earlier observations above remain separate.
