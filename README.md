# omdrop-owl

https://github.com/user-attachments/assets/b195ce4c-e078-49be-bc13-44a72b6dc189

The radio half of [omdrop](https://github.com/brentkearney/omdrop-plugin) for
machines without Apple's Broadcom Wi-Fi. AWDL runs in userspace through
[OWL](https://github.com/jedbillyb/owl) on a monitor interface, and omdrop's own
receiver and sender run over it unchanged. First target: the MediaTek MT7925
(`mt7925e`), as in the Framework 13, where AirDrop works in both directions
while Wi-Fi stays connected. An Intel AX201 works in an "exclusive" mode that
takes Wi-Fi away while the machine is visible.

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

Cards that can't share the AP's channel use [exclusive mode](#exclusive-mode)
instead.

From omdrop-awdl we reuse, unmodified, the tools that only talk to `awdl0` or
BlueZ: `send-to-peer`, `airdrop-send.py`, `ble-airdrop-adv.py`,
`awdl-airdrop-adv.py`, `awdl-mdns-respond.py` and the modules they import. They
are fetched at a pinned commit by `tools/stage.sh`, never committed here.

## Status

`omdrop-discoverable` implements the whole contract. Checked on the MT7925:
`start` returns in about 2 s with `awdl0` usable, announcements going out and
the phone listed by `peers`; a second `start` returns 5 and adjusts the window;
`stop` tears down in about 2 s; a window expires on its own.

## Supported hardware

What omdrop-owl does on each Wi-Fi driver comes from
[`userspace/owl-profiles`](userspace/owl-profiles), one line per driver:

| Driver | Card | Status |
|---|---|---|
| `mt7925e` | MediaTek MT7925 (Framework 13) | ✅ Tested: both directions, Wi-Fi stays connected |
| `iwlwifi` | Intel AX201 | ✅ Tested: both directions on Ubuntu 24.04 (kernel 6.8), Wi-Fi is off while visible ([exclusive mode](#exclusive-mode)) |
| `iwlwifi` | Intel AX200 | ❓ Untested in exclusive mode. Shared mode doesn't work: the driver drops injected frames while connected ([#1](https://github.com/t4t5/omdrop-owl/issues/1)) |
| `iwlwifi` | Intel AX211 | ❓ Untested in exclusive mode. Shared mode doesn't work, monitor mode never ACKs, and an ad-hoc interface beside a connected station crashed its firmware ([#4](https://github.com/t4t5/omdrop-owl/issues/4)) |

The profile is per driver, so the `iwlwifi` line covers every Intel card: the
AX200 and AX211 run in exclusive mode too, without the opt-in below.

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
3. Run `sudo tools/test-card.sh`. It walks you through a photo each way,
   watches Wi-Fi for five minutes after teardown, and writes a report.
4. To see if your card needs `reconnect yes`, run it again after
   `echo 0 | sudo tee /etc/omdrop/reconnect-after`. If Wi-Fi stops after
   teardown, it does (reload the driver to recover). Delete the file after.
5. If something fails, try the other `mon_mac` setting.
6. Open a pull request adding your line to `userspace/owl-profiles`, and paste
   the report's `summary.txt`. The other files include your router's MAC.

Cards that can't inject while connected can try `mode exclusive`, which takes
Wi-Fi away for the window.

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
helper, and a NetworkManager rule keeping `awdl0`, `mon0` and `awdlibss0`
unmanaged. It conflicts with `brcmfmac-awdl-dkms`: one radio backend at a time.

Then install omdrop itself (a version with radio-backend support) and turn it
on from the bar. `/usr/lib/omdrop/omdrop-discoverable probe` says what, if
anything, is in the way.

For development: `just build` assembles the same files in `build/lib`, and
`just test` runs the card test against them.

## Exclusive mode

An Intel AX201 passes up no AWDL frames while associated, so its profile says
`mode exclusive`: Wi-Fi is off while the machine is visible, and `stop` gives
it back to NetworkManager.

- **An ad-hoc (IBSS) interface joins AWDL's BSSID**, so the firmware ACKs the
  phone's unicast and sees its ACKs, which a monitor interface alone never
  does.
- **The cell is HT20**, because the iPhone sends at HT rates and ignores us
  until it restarts if we can't ACK them.
- **It runs on channel 6**: the helper tries 44 and 149 first, but the AX201
  won't start an ad-hoc cell on 5 GHz.
- **It beacons every 10 s**, since its beacons carry AWDL's BSSID and a
  restarted iPhone didn't list us at the usual rate.
- **OWL injects through a monitor interface beside it** with `-F`
  (`owl-03`): multicast in any slot, and unicast whenever the phone is on our
  channel, sent once without waiting for an ACK (`owl-05`) so a missed frame
  doesn't stall the queue behind 15 retries.
- **OWL advertises our channel in all 16 slots** with `-S pin` (`owl-06`), and
  **elects its sync master by metric** with `-E` (`owl-04`), as Apple devices
  do.

## Known issues

- **Deleting a monitor interface while the station is associated wedges the
  MT7925.** A bare monitor interface, added and deleted with nothing else
  running, leaves the station "Connected" but receiving nothing, from seconds
  to a few minutes later, until `mt7925e` is reloaded. That makes it an
  mt76/firmware bug. omdrop's contract forbids the radio helper from reloading
  the driver, so `stop` forces a reconnect right after deleting the interface
  instead. That has kept the station healthy in every test so far.
- **Sending is slower than receiving** (about 490 kB/s against 1.3 MB/s).
  Injected frames leave at a fixed pace of about one every 2.5 ms, whatever
  PHY rate OWL requests (`owl -R`, from `patches/owl-01-tx-rate.patch`) and
  however many slots the phone offers.
- **In shared mode the AP has to be on channel 6, 44 or 149.** Otherwise
  `start` exits 3 and says so.
- **Intel cards are slow, and leave you without Wi-Fi while visible.** The
  AX201 runs AWDL on channel 6, which an iPhone gives one or two slots in
  sixteen when idle and more during a transfer: a 2.4 MB photo took 17 s from
  an iPhone and 10.5 s to it. An iPad beside the iPhone connected once and
  then stopped ACKing our frames; why isn't known.
- **iPhones randomise their AWDL address**, so nothing here remembers a peer.
