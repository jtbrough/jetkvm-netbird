# JetKVM's official Tailscale installer

Notes from reviewing `https://jetkvm.com/install-tailscale.sh` and its
documentation page before finalizing this repo's own install scripts.
Referenced here for context; this repo does not depend on it.

## Runs on the operator's machine, not the device

The script executes locally (`curl -fsSL https://jetkvm.com/install-tailscale.sh
| sh -s -- <jetkvm-ip>`) and does the download and checksum verification
there, on a machine with a working CA trust store. It then transfers the
already-verified tarball to the device with:

```sh
ssh root@"$JETKVM_IP" "cat > /userdata/tailscale.tgz" < "$TMP_FILE"
```

the same pattern this repo uses to stage its own scripts on the device,
independently arrived at (see
[jetkvm-behavior.md](jetkvm-behavior.md#no-sftp-server)). Only after the
verified bytes are on the device does it SSH in again to extract, run
`tailscale configure jetkvm`, and reboot.

This design sidesteps the device's missing CA trust store for the binary
download specifically. It does not need to solve TLS trust on-device at
all for that step, because the device never makes an outbound HTTPS
request to fetch the binary.

## Version pinning

`-v/--version` pins a specific release; omitted, it resolves current
stable from `pkgs.tailscale.com`. Matches this repo's `NETBIRD_VERSION`
(default `latest`, resolved from GitHub's releases API).

## `--clean`

Deletes existing Tailscale data before installing, forcing a new machine
identity. This repo's `NB_CLEAN_INSTALL` env var is the same idea, added
after reviewing this script.

## Reboots and validates post-reboot, not just post-install

The script reboots the device as its last step and polls
(`ssh ... 'tailscale version'`) until it responds, rather than treating a
live-session start as sufficient. This repo adopted the same discipline
after finding two real bugs (crond startup ordering, `tun.ko` not being
loaded) that only manifested across an actual reboot and were invisible
when the daemon was started live in the same SSH session that installed
it. A live start and a boot-time start are not the same claim.

## `tailscale configure jetkvm`

Once the verified tarball is in place, the device-side setup is three
lines: extract, `./tailscale configure jetkvm`, reboot. Tailscale ships a
JetKVM-aware subcommand in their own CLI that handles the
persistence-across-reboot problem this repo solves by hand in
`scripts/netbird-init.sh` and `scripts/watchdog.sh`. There is no NetBird
equivalent. If any part of this repo is worth proposing upstream, a
`netbird configure jetkvm` (or a more general `netbird configure
embedded`, since the "`/userdata` survives OTA, `/` doesn't" pattern isn't
unique to this device) living inside NetBird's own CLI would be a
materially better fix than a third-party installer repo - it's owned by
the people who can actually maintain it against future NetBird releases.

## Why Tailscale doesn't need the CA bundle this repo needs

Tailscale's daemon connects fine to `controlplane.tailscale.com` from a
device with zero CA trust store, using the exact `--clean` install flow
above. This isn't Tailscale avoiding the problem cleverly - its
coordination-server protocol is
[Noise-based](https://tailscale.com/blog/how-tailscale-works) with a
pinned server key, not generic TLS backed by the system's X.509 trust
store. NetBird's management connection is plain gRPC-over-TLS, which
genuinely requires a working CA bundle to verify the server's
certificate. See
[netbird-behavior.md#tls-trust-store](netbird-behavior.md#tls-trust-store)
for the concrete failure mode this causes and how this repo addresses it.
This is a real protocol difference between the two projects, not a gap in
either implementation.
