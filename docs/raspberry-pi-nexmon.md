# Experimental Raspberry Pi 4 integration with Nexmon

OWL can receive native AirDrop transfers through the Raspberry Pi 4's onboard
BCM43455c0 with a patched Nexmon driver and firmware. Stock `brcmfmac` rejected
monitor mode on the tested installation. This report documents the working
radio configuration and the lifecycle a future backend needs to implement.

The packaged `omdrop-discoverable` launcher currently implements shared mode
and an IBSS-based exclusive mode. Neither sets up this Nexmon path. Do not mark
all `brcmfmac` hardware as tested by adding a profile row: that driver name
also covers other chips, firmware versions, and unpatched installations.

## Tested combination

| Component | Version |
|---|---|
| Board | Raspberry Pi 4 Model B Rev 1.1, 2 GB, onboard BCM43455c0 |
| OS | Raspberry Pi OS Lite 64-bit, Debian 13 |
| Kernel | `6.18.50+rpt-rpi-v8` |
| Firmware | `7.45.265 (28bca26 CY)` with the packet ownership fixes below |
| Nexmon base | `kimocoder/nexmon`, `monitor-injection-k7.2`, `650275abbede65507e5ce3b3c1f417b87da1279d` |
| omdrop-owl | `a063387fa8489b206f7d5dd8ed82b79825b1111f` |
| OWL | The `832d70f815c3d4a06a02117bf0fc5e868daa1ff0` pin plus this repository's patches |
| Portable discovery tools | omdrop-awdl `534f91a525337951ca19c311e53d333bd6d55100` |
| Receiver | omdrop-plugin `6af4908310a4fcd1ba7800fcc7b83156bbd7ee77` |

The Nexmon base comes from [upstream PR 692](https://github.com/seemoo-lab/nexmon/pull/692).
It needs the additional [BCM43455c0/7.45.265 packet handling fixes](https://github.com/kimocoder/nexmon/pull/2)
before sustained transfers are reliable. In particular, SDIO can deliver a `PKTLINK` batch to
the injection hook; processing only the head strands the remaining buffers.
The observed result was an exhausted packet pool and a closed SDPCM credit
window, with both transfers and firmware control requests stalled.

The tested firmware also removes unmatched MAC-resume calls, preserves packet
allocation ownership, and uses the target firmware's RX handoff and release
paths. Keep these firmware changes in Nexmon. A userspace restart cannot
repair firmware that has already lost its packet buffers.

## Build and staging requirements

Use Ethernet or a local console for administration. This setup occupies the
onboard radio, so its normal Wi-Fi connection is unavailable while OWL runs.

Build OWL and its portable tools with `tools/build-owl.sh` and `tools/stage.sh`.
Nexmon is a separate prerequisite: build its firmware target
`patches/bcm43455c0/7_45_265-28bca26-CY/nexmon` and its matching
`patches/driver/brcmfmac_6.18.y-nexmon` module against the running kernel's
headers. Source Nexmon's `setup_env.sh` before building; the ARMv7 firmware
compiler also needs the armhf compatibility libraries on a 64-bit Pi OS.

Stage `brcmfmac.ko`, `nexutil`, and a private firmware tree in a root-owned
directory. The firmware tree must provide `brcm/brcmfmac43455-sdio.bin`, with
the board's stock NVRAM/calibration and regulatory assets still available.
Keep the distribution's installed module and firmware intact for rollback.
Before changing radio state, compare `modinfo -F vermagic` for the staged
module with `uname -r`. Rebuild after a kernel update; stop if they differ.

## Radio lifecycle

The sequence below describes the manually supervised setup that was tested.
`STA`, `PHY`, `MAC`, `NEXUTIL`, and `OWL` in the command examples denote the
selected station interface, its PHY, the session MAC, and the staged binaries.
A packaged backend still needs to own these steps and their failure cleanup.

1. Stop any existing AWDL backend. Record the normal NetworkManager connection
   UUID and the existing `/sys/module/firmware_class/parameters/path` value.
   Make the station and both virtual interfaces unmanaged **before** loading
   the replacement module. A temporary NetworkManager rule must match the
   station's name as well as `mon0` and `awdl0`; setting the old interface
   unmanaged alone raced NetworkManager when the new interface appeared.

   For a station named `wlan0`, the temporary rule is:

   ```ini
   [keyfile]
   unmanaged-devices=interface-name:wlan0;interface-name:mon0;interface-name:awdl0
   ```

   Place it under `/run/NetworkManager/conf.d/` and reload NetworkManager's
   configuration. Remove only this integration's temporary file at teardown.

2. Unload the stock `brcmfmac` driver and any associated vendor module, set
   the firmware search override to the private tree, then load the staged
   module. Wait for the station interface to appear and keep it unmanaged.
   Assign a fresh locally administered unicast MAC while the interface is
   down. Reuse that address throughout this radio session. Changing it after
   a full restart avoids peers retaining the previous AWDL sequence state.

3. Bring the station up and create `mon0` on the same PHY:

   ```sh
   ip link set "$STA" up
   iw phy "$PHY" interface add mon0 type monitor
   ip link set mon0 up
   "$NEXUTIL" -I "$STA" -k149/20
   "$OWL" -i mon0 -c 149 -N -S pin -F -E -f -m "$MAC"
   ```

   OWL runs in the foreground here; a supervisor must own its lifetime.
   The tested setup uses fixed channel 149 at 20 MHz and no IBSS interface.
   Use a channel permitted by the local regulatory domain. Other channels
   were not qualified in this test. `-f` disables OWL's peer RSSI cutoff;
   the default cutoff discarded the test peer at ordinary indoor range.

4. Once OWL has created `awdl0`, run the following from the supervising
   process or a second administrative session:

   ```sh
   ip link set "$STA" up
   iw dev "$STA" set power_save off
   "$NEXUTIL" -I "$STA" -m2
   "$NEXUTIL" -I "$STA" -k149/20
   ```

   Reasserting 20 MHz matters: OWL's initial channel request used HT40+.
   Wait until `awdl0` has a non-tentative link-local IPv6 address before
   starting the receiver and advertisers.

5. Run the AirDrop receiver as an unprivileged user. Its service record and
   BLE announcement must refer to this receiver's AWDL identity and listening
   port. Use the portable mDNS advertiser on `awdl0` with `--plain --flags 137`;
   OWL supplies the AWDL encapsulation. The tested announcement cadence was
   `--count 64 --interval 0.0164`, followed by a three-second pause and repeat.
   Start receiver/discovery processes again whenever `awdl0` is recreated,
   since their sockets can retain the old interface/address.

## Health checks and teardown

Checking the OWL process alone misses a firmware stall. `nexutil` can also exit
successfully after an unsuccessful control exchange, so inspect its response:

```sh
"$NEXUTIL" -I "$STA" -g400   # capabilities: 07 00 00 00 on this build
"$NEXUTIL" -I "$STA" -g107   # WLC_GET_MONITOR: 02 00 00 00 while running
```

Use bounded timeouts and retry once before recovery. Command **107** reads
monitor mode; command **108** sets it. A health probe must not issue 108.
The tested supervisor checked every 30 seconds. Before unloading a stalled
radio, preserve a bounded kernel log and available firmware/bus diagnostics.

Recovery stops the receiver, discovery processes, and OWL, then reloads the
radio and starts every AWDL consumer against the newly created interface.
An incomplete transfer must be resent. With systemd, keep the short oneshot
health service outside the target it restarts, and enqueue the restart with
`systemctl --no-block`: otherwise the recovery action can stop its own caller.

For normal shutdown or failed startup, stop the consumers before removing
their interfaces. Unload the experimental module, restore the saved firmware
search path, remove the temporary NetworkManager rule, reload its configuration,
and load the distribution's stock driver. Make the station managed again and
reactivate the saved connection UUID when available. This also needs to work
after a partially completed startup. The tested teardown restored normal
Wi-Fi without replacing the stock files.

## Transfer evidence and limits

- Four consecutive rounds of nine incoming files: **36/36 successful**, about
  **65.3 MB** total, without restarting the radio. The matrix covered JPEG,
  HEIC, and PNG at 480×640, 1200×1600, and 3024×4032 pixels, approximately
  26 KB to 6.6 MB per transfer. All received sizes and SHA-256 hashes matched.
- The repeated-transfer sender used macOS Network.framework's peer-to-peer
  policy to reach AWDL and sent pinned-TLS Discover/Ask/Upload requests with
  DVZip/CPIO. This exercises the transport separately from Finder's sender.
- Native Finder AirDrop reported Sent for a mixed three-file **13.1 MB** batch
  after reboot and controlled recovery; all received hashes matched. A native
  iPhone transfer of approximately **1.9 MB** also arrived successfully, with
  Sent confirmed on the sender.
- The firmware's idle packet pool returned to 33 available buffers after the
  repeated run. Recovery was exercised by disabling monitor mode, then
  verifying that the supervisor recreated the radio and restored mode 2.
  Subsequent healthy checks left that radio session unchanged.

These measurements used the combined firmware changes and a receiver listener
with `SO_RCVBUF` and Linux `TCP_WINDOW_CLAMP` set to 8192 bytes. That optional
receiver change is a separate concern and is not supplied by this guide.
The tests do not isolate the benefit of each supporting firmware change or
establish performance with the default receive window.

Only incoming AirDrop on this Pi 4/kernel/firmware combination was qualified.
Outgoing transfers, Contacts Only, other Pi models or firmware versions, and
the packaged launcher's full lifecycle remain unqualified. The guide is a
starting point for an explicit Nexmon backend, not a universal driver profile.
