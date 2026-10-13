# RTL8852AE shared-mode observations

Tested 2026-10-14 on a ThinkPad P14s Gen 2a (Lenovo 21A1), Realtek RTL8852AE
PCI `10ec:8852`, `rtw89_8852ae`, Ubuntu 26.04.1 LTS, kernel
`7.0.0-38-generic`. Peer: iPhone 13, iOS **26.6.2 as reported by the tester**.
Wi-Fi was associated on 2.4 GHz channel 6. Ethernet carried the computer's
internet connection during testing. AirDrop used Everyone mode and a local
self-signed identity.

Hardware evidence is from omdrop-owl commit
`a063387fa8489b206f7d5dd8ed82b79825b1111f`, packaged as 0.1.0-1,
OWL `832d70f` with eight patches and omdrop-awdl helpers `534f91a`.
Receiver: omdrop-plugin `6af4908` (0.16.1) with local Ubuntu readiness fixes
(dpkg version comparison when vercmp is absent; load libkeyutils by soname).
The newer upstream changes used as this report's PR base were not hardware-tested.

Profile exercised: `rtw89_8852ae shared station yes no` (generic opt-in
fallback). The proposed explicit profile preserves that behavior and **stays
untested/opt-in** because recovery reliability is unresolved.

## Completed runs

| Measurement | Sending run | Receiving run |
| --- | --- | --- |
| Local start time | 00:37:00 +08:00 | 01:00:08 +08:00 |
| Baseline gateway pings | 10/10 | 4/10 |
| Radio startup | 212 ms | 262 ms |
| Phone heard / OWL sync | yes | yes |
| Computer to iPhone | 5,294-byte test PNG; HTTP 200; sender exit 0, 10 s | Not successful: phone did not open 8770; sender exit 3 after 61 s; tester selected skip |
| iPhone to computer | Skipped, receiver absent | Photo saved; Upload HTTP 200 |
| Wi-Fi gateway replies while active | 22/22, longest gap 0 s | 363/367, longest gap 1 s |
| Stop | exit 0, 8,887 ms | exit 0, 9,356 ms |
| Full 300-ping recovery check | 298/300, longest gap 1 s | 280/300, longest gap 8 s |

Sanitized receiver evidence:

```text
01:00:47.923 POST /Upload
01:01:54.687 upload: decoded to 3838464 bytes, magic b'070707'
01:01:54.700 upload: stored <photo>.JPG
01:01:54.700 "POST /Upload HTTP/1.1" 200
```

The observed upload interval is approximately 67 seconds. It is not a
controlled throughput benchmark: the decoded archive size is not the JPEG's
size or the wire byte count, and no bottleneck was isolated.

## Limits and follow-up

Both directions worked across separate runs, **not in the same completed run**.
Receiving was slow, and Wi-Fi reliability cannot be claimed: the receiving
run already had loss in its baseline, and its recovery check had an 8-second
gap despite `reconnect yes`. No causal attribution to the driver, router,
interference, or teardown is established. Ethernet kept internet usable but
does not establish healthy Wi-Fi.

The necessity of `reconnect yes` was not isolated; it was retained from the
fallback. Channels 44/149, other Realtek variants, other iOS versions,
Contacts Only mode, and large/multiple transfers were not tested.

An earlier run lacked the local self-signed identity and failed before sending.
Another successful send had an interrupted 55-ping recovery check. Neither is
used as a completed stability run. The live ping display counts delayed
`no answer` messages; final reply counts above are the test's completed
summaries, not that interim counter.

Next useful tests: repeat both directions in a single run; compare a longer
idle Wi-Fi baseline; isolate reconnect behavior; measure larger transfers.
