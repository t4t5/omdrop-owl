# omdrop-owl

The radio half of [omdrop](https://github.com/brentkearney/omdrop-plugin) for
machines without Apple's Broadcom Wi-Fi. AWDL runs in userspace through
[OWL](https://github.com/jedbillyb/owl) on a monitor interface. First target: the
MediaTek MT7925 in a Framework 13, where AirDrop works in both directions with
Wi-Fi staying connected (see
[linux-airdrop](../linux-airdrop/README.md) for the research and measurements).

It is a sibling of [omdrop-awdl](https://github.com/brentkearney/omdrop-awdl),
the Broadcom radio package, and plugs into omdrop the same way: helpers in
`/usr/lib/omdrop` that the omdrop CLI and panel call.

## Layout

```
userspace/omdrop-discoverable   ours: the radio helper, OWL-based, same
                                contract as omdrop-awdl's
tools/stage.sh                  assembles build/lib, laid out like /usr/lib/omdrop
build/lib/                      (generated) ours + omdrop-awdl's radio-independent tools
upstream/omdrop-awdl/           (generated) fetched at a pinned commit
```

From omdrop-awdl we reuse, unmodified, everything that only talks to `awdl0`
or BlueZ: `send-to-peer`, `airdrop-send.py`, `ble-airdrop-adv.py`,
`awdl-airdrop-adv.py`, `awdl-mdns-respond.py` and their modules. They are
fetched by `tools/stage.sh`, not committed: omdrop-awdl is GPL-2.0-only, so
how they ship is a packaging decision to make deliberately.

## Status

- linux-airdrop's test 70 showed omdrop's receiver, sender, announcer and BLE
  wake all work over OWL unmodified, in both directions, with this
  `omdrop-discoverable peers` feeding `send-to-peer`.
- `omdrop-discoverable peers` works (OWL's peers, from its log at the fixed
  `/run/omdrop-owl/owl.log`: callers come through pkexec, which drops the
  environment).
- `start`, `stop` and `status` are next, ported from linux-airdrop's
  `lib/awdl.sh`.
- Then: OWL built and installed root-owned into `/usr/lib/omdrop` (pinned, with
  linux-airdrop's patches), a polkit policy, and a PKGBUILD.

## Known issues to design around

- The station wedges seconds to minutes after the monitor interface is
  deleted, until `mt7925e` is reloaded. linux-airdrop's test 15 reproduced it
  with a bare monitor vif and nothing else, so it's an mt76/firmware bug.
  omdrop's contract forbids the radio helper from reloading the driver, so
  `stop` has to tear down in a way that avoids it. Forcing a reconnect right
  after the delete (test 15's phase N, what `stop` does) and reconnecting
  around the delete (phase R) both avoided it for 240 s, one run each.
- Sending is ~490 kB/s, receiving ~1.3 MB/s, limited by OWL's injection path.
