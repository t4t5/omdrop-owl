# omdrop-owl

https://github.com/user-attachments/assets/b195ce4c-e078-49be-bc13-44a72b6dc189

The radio half of [omdrop](https://github.com/brentkearney/omdrop-plugin) for
machines without Apple's Broadcom Wi-Fi. AWDL runs in userspace through
[OWL](https://github.com/jedbillyb/owl) on a monitor interface, and omdrop's own
receiver and sender run over it unchanged. First target: the MediaTek MT7925
(`mt7925e`), as in the Framework 13, where AirDrop works in both directions
while Wi-Fi stays connected.

It is a sibling of [omdrop-awdl](https://github.com/brentkearney/omdrop-awdl),
the Broadcom radio package, and plugs into omdrop the same way: helpers in
`/usr/lib/omdrop` that the omdrop CLI and panel call. The contract is described
in omdrop's `docs/radio-backend.md`.

## How it works

The Wi-Fi station stays associated, and AWDL shares its channel:

1. **AWDL runs on the access point's own channel**, which has to be 6, 44 or
   149 (AWDL's channels). An iPhone spends a large share of its AWDL time slots
   on those channels, so the radio never has to leave the AP.
2. **A monitor interface carries the station's MAC**, and OWL runs on it with
   `-S intersect`, advertising only the phone's slots on that channel.
3. **The MT7925 sends injected frames from the station's MAC regardless**, and
   the station interface ACKs the phone's unicast to that MAC, so no "active"
   monitor interface is needed.
4. OWL creates `awdl0`. omdrop's receiver binds to it, and omdrop-awdl's
   `awdl-airdrop-adv.py --plain` announces `_airdrop._tcp` on it every few
   seconds (`--plain`, because OWL adds the AWDL encapsulation itself).

## Layout

```
userspace/omdrop-discoverable   the radio helper (start, stop, status, peers, probe)
userspace/owl-profiles          per-driver settings: the supported hardware
patches/owl-*.patch             our changes to OWL, applied in name order
tools/build-owl.sh              builds OWL at a pinned commit, with the patches
tools/stage.sh                  assembles build/lib, laid out like /usr/lib/omdrop
tools/build-deb.sh              packs build/lib into a .deb (PKGBUILD's counterpart)
packaging/deb/                  the .deb's maintainer scripts
build/lib/                      (generated) ours, OWL, and omdrop-awdl's portable tools
upstream/                       (generated) OWL and omdrop-awdl at pinned commits
```

From omdrop-awdl we reuse, unmodified, the tools that only talk to `awdl0` or
BlueZ: `send-to-peer`, `airdrop-send.py`, `ble-airdrop-adv.py`,
`awdl-airdrop-adv.py`, `awdl-mdns-respond.py` and the modules they import. They
are fetched at a pinned commit by `tools/stage.sh`, never committed here.

## Status

- `omdrop-discoverable` implements the whole contract. Checked on the MT7925:
  `start` returns in under 2 s with `awdl0` usable, announcements going out and
  the phone listed by `peers`; a second `start` returns 5 and adjusts the
  window; `stop` tears down in about 2 s; a window expires on its own.
- omdrop's receiver, sender, announcer and BLE wake all work over it,
  unmodified, in both directions.

## Supported hardware

What omdrop-owl does on each Wi-Fi driver comes from
[`userspace/owl-profiles`](userspace/owl-profiles), one line per driver:

| Driver | Card | Status |
|---|---|---|
| `mt7925e` | MediaTek MT7925 (Framework 13) | Tested: both directions, Wi-Fi stays connected |

Any other card falls back to the table's `*` line, which only runs once you
opt in with `echo 1 | sudo tee /etc/omdrop/allow-untested`.

### Adding your card

Cards that can inject frames from a monitor interface while connected to Wi-Fi
are the likely candidates. Most mac80211 drivers can, but how they behave
around it varies, which is what the profile records.

1. Find your driver: `basename $(readlink /sys/class/net/<wifi>/device/driver)`.
   Put your AP on channel 6, 44 or 149.
2. Opt in (`/etc/omdrop/allow-untested`), and copy the `*` line to
   `/etc/omdrop/owl-profiles` with your driver's name. That file is read before
   the packaged table, so you can change settings without rebuilding.
3. Try it: turn omdrop on, send a photo from an iPhone, send one back, and turn
   it off. Then watch Wi-Fi for five minutes (`ping` your router): if it stops
   receiving after omdrop turns off, keep `reconnect yes`.
4. If something fails, try the other `mon_mac` setting. Report what you saw
   either way.
5. Open a pull request adding your line to `userspace/owl-profiles`, with
   `status tested` and, in `notes`, the card, kernel version and what you
   observed.

Cards that can't inject while connected need an "exclusive" mode, which takes
Wi-Fi away for the window. That mode doesn't exist yet; an issue with what you
found is welcome.

## Install

On Arch:

```sh
makepkg -si
```

On Debian or Ubuntu:

```sh
sudo apt install build-essential cmake git pkg-config dpkg-dev \
  libev-dev libpcap-dev libnl-3-dev libnl-genl-3-dev
tools/build-deb.sh
sudo apt install ./omdrop-owl_*.deb
```

Either way, this builds OWL at the commit pinned in `pins`, with `patches/`,
and installs it root-owned into `/usr/lib/omdrop` together with
`omdrop-discoverable` and omdrop-awdl's portable tools, a polkit policy for the
helper, and a NetworkManager rule keeping `awdl0` and `mon0` unmanaged. It
conflicts with `brcmfmac-awdl-dkms`: one radio backend at a time.

Then install omdrop itself (a version with radio-backend support) and turn it
on from the bar. `/usr/lib/omdrop/omdrop-discoverable probe` says what, if
anything, is in the way.

For development without installing, `tools/build-owl.sh` and `tools/stage.sh`
assemble the same files in `build/lib`.

## Known issues

- **Deleting a monitor interface while the station is associated wedges the
  MT7925.** A bare monitor interface, added and deleted with nothing else
  running, leaves the station "Connected" but receiving nothing, from seconds
  to a few minutes later, until `mt7925e` is reloaded. That makes it an
  mt76/firmware bug. omdrop's contract forbids the radio helper from reloading
  the driver, so `stop` forces a reconnect right after deleting the interface
  instead. In testing, that kept the station healthy for the four minutes
  watched after every teardown.
- **Sending is slower than receiving** (about 490 kB/s against 1.3 MB/s).
  Injected frames leave at a fixed pace of about one every 2.5 ms, whatever
  PHY rate OWL requests (`owl -R`, from `patches/owl-01-tx-rate.patch`) and
  however many slots the phone offers.
- **The AP has to be on channel 6, 44 or 149.** Otherwise `start` exits 3 and
  says so. Taking the card off the AP for the duration of a window would lift
  this, but isn't implemented.
- **iPhones randomise their AWDL address**, so nothing here remembers a peer.
