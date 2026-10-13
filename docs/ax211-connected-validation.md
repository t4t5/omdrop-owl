# AX211 connected-mode validation, 12 October 2026

Dell XPS 9320, Intel AX211 PCI 8086:51f0, kernel 7.2.8-5-omarchy-bore,
firmware 89.d2579d43.0. Stock driver throughout. Managed Wi-Fi stayed on
channel 36; the secondary GO used channel 6. No second adapter was used. The Apple peer was an iPhone 16 Pro on iOS
26.6.2 (owner-reported); both sides used Everyone visibility.

## Installed omdrop path

The candidate was built as a pacman package and installed in /usr/lib/omdrop.
The normal installed plugin controls it through the existing backend contract.
Its existing local receiver settings use compact TLS, a 1024-byte/s minimum
read rate, an EC self-signed identity and a receiver-bound BLE advertisement.
Those settings and the user's identity were preserved. The test does not
qualify a default RSA receiver or a plugin lacking compact TLS support.

- Normal `omdrop on` started the receiver and reported visibility.
- `omdrop peers -n` resolved the phone's name.
- `omdrop send "iPhone" FILE` sent the original 272,892-byte PNG in 3.14 s;
  the user confirmed receipt.
- The normal receiver stored a 402,031-byte JPEG and a 3,853,909-byte PNG.
  Both uploads returned HTTP 200; the larger transfer took about 17 s.
- An earlier 3,369,948-byte incoming photo stalled near the end, then returned
  HTTP 408 after 30 s without progress. This remains an unresolved reliability
  observation, not a receiver timeout that was bypassed or hidden.
- All 1,200 gateway probes in the ten-minute transfer observation passed.
- Timed expiry removed the radio interfaces and stopped the receiver/BLE unit.
- SIGKILL of the systemd radio supervisor triggered ExecStopPost cleanup;
  only the original managed interface and pre-existing P2P device remained.

Raw captures and logs are local outside the repository because they contain
network and device identifiers. No photos or private headers belong in a PR.

## Automated checks

The native helper builds with warnings treated as errors and passes its beacon
self-test. Python checks cover profile precedence, legal channels, partial-start
cleanup, interface ownership changes, service collection, systemd ownership and
JSON status compatibility. Existing exclusive-mode checks pass. The upstream
A-MSDU overflow regression passes under AddressSanitizer outside the tracing
sandbox. Local and release-style AUR builds succeeded.

## Limits

This remains an experimental, hardware-specific profile. Roaming intentionally
ends the window; IPv6-only networks and gateways that do not answer ping are
not supported by this mode. Other AX211 IDs, kernels and firmware are not
qualified. The stock Intel unassociated-injection warning remains. Large-file,
suspend/resume and long-running reliability need broader testing.
