# NetBird client behavior

Findings about the `netbird` CLI/daemon relevant to running it outside a
normal Linux distribution - no systemd, no package manager, no system CA
store. Verified against client v0.78.0/v0.78.1
([netbirdio/netbird](https://github.com/netbirdio/netbird)).

## `service run` does not connect anything by itself

`netbird service run --config <path>` starts the daemon. It does not
establish a connection to the management server on its own - not even for
an already-registered peer with valid persisted keys. An explicit
`netbird up` is required after every daemon start.

This matches NetBird's own Docker entrypoint
(`client/netbird-entrypoint.sh`): start the service, wait for it to
respond to `status`, then call `up`. `scripts/netbird-init.sh` follows the
same two-step pattern.

## Setup keys are single-use, at registration only

A setup key is consumed the first time a peer registers. Reconnecting an
already-registered peer needs only `--management-url`; passing
`--setup-key` again is unnecessary (and, for a placeholder/invalid value,
apparently harmless - the client uses the peer's already-persisted private
key for the connection, not the setup key, once registered). This repo's
`install.sh` only requires `NB_SETUP_KEY` when no existing peer state is
present.

## The `up` subcommand is not optional syntax

`--config`, `--management-url`, and `--setup-key` are registered as
persistent flags on the CLI's root command, not specifically on `up`.
Given a bare invocation like:

```sh
netbird --config /path --management-url https://mesh.example.com up
```

cobra parses the flags fine regardless of where `up` appears in the
argument list relative to them - but if the literal `up` token is dropped
entirely, cobra treats the invocation as "no subcommand given," prints the
root command's help text, and **exits 0**. Not an error, not a non-zero
exit code - a normal shell script checking `$?` after this will proceed as
if the connection attempt succeeded. Always include the literal `up`
argument; don't rely on flag presence alone to imply the subcommand.

<a name="management-url"></a>
## `ManagementURL` is stored as a structured object, not a string

The persisted config (`default.json`, or whatever `--config` points at)
stores the management URL as a full `url.URL`-shaped JSON object:

```json
"ManagementURL": {
    "Scheme": "https",
    "Host": "mesh.example.com:443",
    ...
}
```

not a flat string. Parsing this out of the config file to avoid asking
for the value twice is fragile - the field name matches, but the shape
doesn't, and there's no guarantee the internal representation stays
stable across releases. This repo avoids the dependency entirely: `--config`
records the management URL in a bundled `management-url.txt` at
install time, and every other script reads that back instead of NetBird's
own config format.

## `up`'s `--config` flag is deprecated but functional

As of the versions tested, `netbird up --config <path>` prints a
deprecation warning recommending `$NB_CONFIG` or `netbird service
run --config=<path>` instead. It still works correctly; the warning is
informational.

<a name="tls-trust-store"></a>
## TLS trust store is required, and its absence looks like a hang

On a system with no CA bundle (see
[jetkvm-behavior.md](jetkvm-behavior.md#no-ca-trust-store)), every TLS
dial to the management server fails:

```
transport: authentication handshake failed: tls: failed to verify certificate: x509: certificate signed by unknown authority
```

The daemon logs this and retries with backoff indefinitely rather than
surfacing a fatal error to the CLI. From the outside this looks
indistinguishable from a network hang: the `up` command blocks with no
output. The failure is only visible in the daemon's own log file
(`/var/log/netbird/client.log` by default - not wherever `service run`'s
stdout happened to be redirected, which stays empty).

Fix: point `SSL_CERT_FILE` (a standard Go `crypto/x509` environment
variable, no NetBird-specific flag needed) at a real CA bundle before
starting the daemon.

## Default paths are still touched even with `--config` set elsewhere

<a name="default-paths"></a>
Passing `--config` everywhere does not fully relocate the client's
footprint. Confirmed present on a device after a complete
`--config`-scoped install:

- `/root/.config/netbird/active_profile.txt`
- `/var/lib/netbird/state.json`
- `/var/lib/netbird/resolv.conf`
- `/var/lib/netbird/active_profile.json`
- `/tmp/netbird/client.log`

None of these are read by anything in this repo, but a script aiming for
complete removal needs to delete them explicitly - `rm -rf` on the custom
`--config` directory alone leaves traces behind. `scripts/uninstall.sh`
removes all of the above.

## DNS management replaces `resolv.conf` entirely, with no fallback

When a peer is a member of any nameserver group - regardless of whether
that group is marked `primary` - NetBird's DNS manager replaces the
system's `/etc/resolv.conf` outright with its own local proxy address
(a fixed per-account IP; observed as `100.0.255.254` in testing), rather
than adding itself as one resolver among others. That proxy answers
queries matching the group's configured match-domains and **refuses**
everything else - it does not forward unmatched queries to the
originally-configured system resolvers, because those resolvers are no
longer referenced anywhere in `resolv.conf`.

The nameserver group's `primary` field controls whether it acts as a
catch-all (empty match-domains list) or a scoped resolver (non-empty
list). The management API exposes this as an explicit `primary: bool`,
but as of the dashboard version tested it is not a visible toggle in the
UI - it's derived automatically from whether the "Match Domains" field is
left empty when the group is created or edited
(`primary: !domains.length` in
[netbirdio/dashboard](https://github.com/netbirdio/dashboard)'s
`NameserverModal.tsx`). A scoped (non-primary) group with match-domains
set is not "these domains get special routing, everything else works
normally" - for any peer subject to it, it's "only these domains resolve
at all."

This is invisible on Docker-based installs with `network_mode: host`:
container network-namespace isolation means the container has its own
`/etc/resolv.conf`, separate from the host's, so the host's DNS is
unaffected regardless of what the account's nameserver groups are
configured to do. Native installs (no container boundary) are the first
to expose the real behavior of an existing nameserver-group
configuration - not a regression caused by going native, just the first
time it becomes visible.
