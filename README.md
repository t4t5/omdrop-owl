# omdrop-owl

https://github.com/user-attachments/assets/b195ce4c-e078-49be-bc13-44a72b6dc189

AirDrop between iPhones and Linux laptops whose Wi-Fi isn't Apple's Broadcom
chip. Pairs with [omdrop](https://github.com/brentkearney/omdrop-plugin).

See [supported hardware](#supported-hardware).

## Install

Install this package (omdrop-owl) first, then [omdrop](https://github.com/brentkearney/omdrop-plugin).

On Arch/Omarchy ([AUR](https://aur.archlinux.org/packages/omdrop-owl)):

```sh
yay -S omdrop-owl
```

<details>
<summary>On Debian or Ubuntu (from source)</summary>

```sh
sudo apt install build-essential cmake git pkg-config dpkg-dev \
  libev-dev libpcap-dev libnl-3-dev libnl-genl-3-dev
tools/build-deb.sh
sudo apt install ./omdrop-owl_*.deb
```

This builds OWL at the commit pinned in `pins`, with `patches/`,
and installs it root-owned into `/usr/lib/omdrop` together with
`omdrop-discoverable` and omdrop-awdl's portable tools, a polkit policy for the
helper, and a NetworkManager rule keeping `awdl0`, `mon0` and `awdlibss0`
unmanaged. It conflicts with `brcmfmac-awdl-dkms`: one radio backend at a time.

</details>

Then install omdrop (0.16.0 or newer):

```sh
omarchy plugin add https://github.com/brentkearney/omdrop-plugin.git
```

and turn it on from the bar.


## Supported hardware

- **Shared** mode = Wi-Fi stays connected
- **Exclusive** mode = Wi-Fi is *off* while the machine is visible (see [why](#exclusive-mode))

| Card | Driver | Status | Tested on |
|---|---|---|---|
| MediaTek MT7925 | `mt7925e` | ✅ Shared | Framework 13, `14c3:0717`, Omarchy 4.0.4 (kernel 7.2.5) |
| Intel AX200 | `iwlwifi` | ✅ Exclusive | ThinkPad X1 Yoga, `8086:2723`, NixOS 26.05 (kernel 6.19.8) |
| Intel AX201 | `iwlwifi` | ✅ Exclusive | Ubuntu 24.04 (kernel 6.8); CachyOS (kernel 7.2.9) |
| Intel AX211 | `iwlwifi` | ✅ Exclusive | ThinkPad X1, `8086:51f1`, Ubuntu 26.04 (kernel 7.0); XPS 9320, `8086:51f0`, Arch (kernel 7.2.3) |
| Intel BE (Panther Lake) | `iwlwifi` | ✅ Exclusive | XPS 16, `8086:e440`, Arch (kernel 7.2) |
| MediaTek MT7921 | `mt7921e` | ❌ Exclusive ([#14](https://github.com/t4t5/omdrop-owl/issues/14)); shared untested | `14c3:7961`, CachyOS (kernel 7.2.9) |
| Intel AX210 | `iwlwifi` | ❓ Exclusive untested | — |
| Intel BE200 | `iwlwifi` | ❓ Exclusive untested | — |
| Intel 9260 / 9560 | `iwlwifi` | ❓ Exclusive untested | — |
| MediaTek MT7922 (RZ616) | `mt7921e` | ❓ Untested (opt-in) | — |
| Qualcomm WCN6855 (QCNFA765) | `ath11k_pci` | ❓ Untested (opt-in) | — |
| Qualcomm WCN7850 (FastConnect 7800) | `ath12k` | ❓ Untested (opt-in) | — |
| Realtek RTL8852BE / RTL8852CE | `rtw89_8852be` / `rtw89_8852ce` | ❓ Untested (opt-in) | — |
| MediaTek MT7612U (USB) | `mt76x2u` | ❓ Untested (opt-in), in progress in [#13](https://github.com/t4t5/omdrop-owl/pull/13) | — |

- ✅ means both directions work
- ❌ means that the mode was tried and fails.

One card name can cover chips that behave differently, so a report from a machine, PCI ID
(`lspci -nn`) or kernel not listed here helps too.

The Raspberry Pi 4's BCM43455c0 also has an
[experimental Nexmon integration report](docs/raspberry-pi-nexmon.md), including
isolated firmware defects, radio lifecycle, recovery checks, and validation
limits. Historical incoming-AirDrop tests used a broader experimental firmware
patch; the narrowed companion firmware PR still needs end-to-end validation.
The packaged launcher does not yet implement this backend, and this result
does not qualify stock `brcmfmac` or a generic `brcmfmac` hardware profile.

### Adding your card

What omdrop-owl does on each Wi-Fi driver comes from
[`userspace/owl-profiles`](userspace/owl-profiles), one line per driver, so the
`iwlwifi` line covers every Intel card. A driver with
no line falls back to the `*` line, which only runs once you opt in with
`echo 1 | sudo tee /etc/omdrop/allow-untested`.

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

## How it works

AWDL (the Wi-Fi link AirDrop runs over) is provided by [jedbillyb's OWL fork](https://github.com/jedbillyb/owl).
omdrop's receiver and sender run over
it unchanged. Discovery and transfer tools are reused from omdrop-awdl,
fetched at a pinned commit by `tools/stage.sh`.

### Shared mode

Wi-Fi stays connected on channel **6, 44 or 149**. OWL injects frames through
a monitor interface using the station's MAC, and advertises only the phone's
slots on that channel (`-S intersect`). On the MT7925, the station handles
ACKs. OWL exposes `awdl0` for omdrop's receiver and AirDrop announcements.

### Exclusive mode

No Intel card tested works in shared mode, so `iwlwifi` disconnects Wi-Fi
while the machine is visible and restores it on `stop`.

- An ad-hoc (IBSS) interface joins AWDL's BSSID to handle ACKs. Some AX211s
  need the Wi-Fi interface itself repurposed for this.
- The cell uses HT20 on channel 6 because the tested Intel cards reject
  5 GHz IBSS. Beacons every 10 seconds fix discovery after an iPhone restart.
- OWL injects through a monitor interface, advertises our channel in all
  16 slots (`-S pin`), and elects its sync master by metric (`-E`). Unicast
  frames are sent once to avoid retries stalling the queue.

## Development

`just build` assembles the same files in `build/lib`, and `just test` runs the
card test against them. On Arch, `makepkg -si` (or `just install`) builds and
installs the pacman package from the checkout.

Without the package, copy `packaging/99-omdrop-owl-unmanaged.conf` to
`/etc/NetworkManager/conf.d/` and run `sudo nmcli general reload conf`, or
NetworkManager manages OWL's interfaces and the phone never shows up.

## Known issues

- **Shared mode needs your AP on channel 6, 44 or 149.** On any other channel,
  `start` refuses and says so.
- **The MT7925 drops off Wi-Fi when the monitor interface is removed** (an
  mt76/firmware bug), so `stop` reconnects Wi-Fi straight after.
- **The MT7925 sends slower than it receives** (about 490 kB/s against
  1.3 MB/s): injected frames leave at most one every ~2.5 ms.
- **Intel cards are slow**, since AWDL on channel 6 gets few of the iPhone's
  slots: a 2.4 MB photo takes 10–17 s on an AX201.
