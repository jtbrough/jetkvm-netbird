# JetKVM device behavior

Notes on stock JetKVM firmware relevant to running anything persistent and
network-facing on the device. Verified against firmware built April-May
2026 (kernel 5.10.160, armv7l).

## Boot process and `/userdata`

The root filesystem (`/`) is an OTA-replaceable ext4 image; `/userdata` is
a separate partition that survives firmware updates. The vendor's own boot
script, `/oem/usr/bin/RkLunch.sh`, scans two directories for executable
`S??*` scripts, in this order:

1. `/oem/usr/etc/init.d/` - vendor scripts (video/audio/NPU drivers,
   network bring-up, dropbear, the `jetkvm_app` supervisor).
2. `/userdata/init.d/` - a supported (if undocumented) extension point for
   anything that needs to persist across OTA updates.

Both directories are scanned synchronously, in numeric order, near the
start of boot. Kernel module loading (`/oem/usr/ko/insmod_ko.sh`) and
network bring-up happen afterward, in a separate function
(`post_chk`) that the boot script backgrounds. A script placed in
`/userdata/init.d/` therefore runs **before** most kernel modules are
loaded and before the network interface is up - anything that depends on
either must handle that itself (poll, retry, or load what it needs
directly) rather than assume boot order guarantees readiness.

This repo's boot script lives at `/userdata/init.d/S50netbird`.

## `tun.ko` is not loaded automatically

`/oem/usr/ko/tun.ko` exists on the filesystem but is not in
`insmod_ko.sh`'s load list (which covers camera, audio, and NPU drivers
only), and nothing else loads it either. Any WireGuard client that needs a
kernel TUN device fails outright on first boot with an interface-creation
error. `netbird-init.sh` loads it explicitly on every start:

```sh
insmod /oem/usr/ko/tun.ko 2>/dev/null || true
```

`2>/dev/null || true` because a second `insmod` on an already-loaded
module returns "File exists," which is not a failure condition.

## No init system beyond busybox `init` and the `S` scripts

There is no systemd, no `runit`, no `supervisord`. `crond` is present as a
BusyBox applet but:

- is not started by anything in stock firmware, and
- its spool directory, `/var/spool/cron/crontabs`, lives on the
  OTA-replaceable rootfs and does not survive a reboot.

Both the spool directory and the crontab file must be recreated on every
boot, before `crond` starts - starting `crond` before its spool directory
exists does not fail loudly, it just runs without picking up the
crontab. `netbird-init.sh` handles this ordering explicitly.

## No CA trust store

Stock firmware ships with no `/etc/ssl/certs` at all. `wget`'s own output
makes the implication explicit: `wget: note: TLS certificate validation
not implemented`. This has two consequences:

- `wget` over HTTPS provides no integrity guarantee on this device. Any
  download needs its own out-of-band verification (checksum against a
  value obtained through a channel you already trust).
- Any program that does real TLS/X.509 verification (Go's
  `crypto/x509`, which NetBird uses) fails every TLS handshake to an
  HTTPS endpoint, with no trust store to validate against. See
  [netbird-behavior.md](netbird-behavior.md#tls-trust-store) for the
  specific failure mode and fix.

This repo bundles a CA store (`scripts/ca-certificates.crt`, refreshed via
`scripts/refresh-ca-bundle.sh`) and points `SSL_CERT_FILE` at it rather
than relying on anything present on the device.

## No `sftp-server`

`scp` fails outright (`sh: /usr/libexec/sftp-server: not found`) - modern
OpenSSH clients default to the SFTP subsystem, which this firmware does
not ship. Transfer files with the legacy `cat` pattern instead:

```sh
ssh root@<device-ip> "cat > /path/to/file" < local-file
```

This is also how JetKVM's own official Tailscale installer moves files
onto the device - see
[tailscale-install-script.md](tailscale-install-script.md).

## Native Wake-on-LAN

JetKVM's firmware has its own Wake-on-LAN feature, independent of
anything installed on the device: a JSON-RPC method (`sendWOLMagicPacket`)
and a REST endpoint (`POST /device/send-wol/:mac-addr`), both sending a
real magic packet directly from the JetKVM's own process - no shell-out to
`ether-wake` required, though `ether-wake` is also present at
`/usr/sbin/ether-wake` if you'd rather invoke it over SSH.

The REST endpoint sits behind the same session-cookie auth as the rest of
the web UI (`POST /auth/login-local` with the device password). There is
no long-lived API token for it. For unattended/scripted use this means
storing the device password and performing a scripted login on every
invocation - more moving parts than SSH plus `ether-wake` for the same
outcome, unless you have another reason to prefer the native API.

## Tailscale integration is passive

JetKVM's firmware has no install, update, or uninstall logic for
Tailscale. Its entire native integration
(`internal/tailscale/tailscale.go`, `tailscale.go`, `TailscaleCard.tsx` in
[jetkvm/kvm](https://github.com/jetkvm/kvm)) is:

- `exec.LookPath("tailscale")` to detect whether a binary is on `PATH`;
- shell out to `tailscale status --json` for status;
- shell out to `tailscale set --login-server=<url>` to change the control
  server.

The web UI's Tailscale card does not render at all unless a binary is
already present. Installing, updating, and persisting Tailscale (or any
other VPN client) across reboots and firmware updates is entirely the
user's responsibility, via the `/userdata/init.d` mechanism above. See
[tailscale-install-script.md](tailscale-install-script.md) for how
JetKVM's own installer handles that.
