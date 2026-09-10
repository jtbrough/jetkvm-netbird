# jetkvm/kvm integration

Files and patches meant to be copied into a [jetkvm/kvm](https://github.com/jetkvm/kvm)
checkout, mirroring the existing Tailscale integration
(`internal/tailscale/`, `tailscale.go`, `TailscaleCard.tsx`). Not part of
this repo's own build - `netbird.go` and `ui/components/NetbirdCard.tsx`
depend on jetkvm/kvm's own internal packages and cannot compile outside
that module.

`internal/netbird/` at this repo's root, by contrast, is a real standalone
Go package with its own tests - copy it into jetkvm/kvm's
`internal/netbird/` unchanged.

## Scope decision: status display, not interactive SSO login

Tailscale's card can complete an interactive SSO login because
`tailscaled` keeps the auth URL available on any later `status --json`
call. NetBird's SSO flow is a separate device-code RPC pair
(`Login`/`WaitSSOLogin` in `client/proto/daemon.proto`) that the CLI's
`netbird login` blocks on and prints to its own stdout - not something a
later `status --json` poll can read back. Supporting it properly means
either vendoring NetBird's gRPC daemon client or keeping a backgrounded
`netbird login` process alive to cache its output, a meaningfully heavier
integration than Tailscale's plain CLI shell-out.

This integration detects and displays `NeedsLogin` / `LoginFailed` /
`SessionExpired` states (real values of NetBird's `DaemonStatus`) but does
not implement one-click SSO. A setup-key-based deployment - what this
whole repo's `scripts/` are built for - never hits this path.

## `config.go`

Add alongside `TailscaleControlURL`:

```go
NetbirdManagementURL string `json:"netbird_management_url,omitempty"`
```

## `netbird.go`

Copy `netbird.go` to the repo root. Requires `github.com/jtbrough/jetkvm-netbird/internal/netbird`
as a module dependency (or vendor `internal/netbird`'s contents directly
into jetkvm/kvm's own `internal/netbird/`, matching the Tailscale
integration's pattern of owning the package in-tree - the latter is
probably the better fit unless this repo's package is kept as a
long-term dependency on purpose).

## `jsonrpc.go`

Add to the method registry, alongside the `*Tailscale*` entries:

```go
"getNetbirdStatus":        {Func: rpcGetNetbirdStatus},
"getNetbirdManagementURL": {Func: rpcGetNetbirdManagementURL},
"setNetbirdManagementURL": {Func: rpcSetNetbirdManagementURL, Params: []string{"managementURL"}},
```

## `log.go`

Add alongside `tailscaleLogger`:

```go
netbirdLogger = logging.GetSubsystemLogger("netbird")
```

## `ui/src/hooks/stores.ts`

Add alongside `TailscaleStatus`:

```ts
export interface NetbirdStatus {
  installed: boolean;
  running: boolean;
  daemonStatus?: string;
  managementURL?: string;
  managementError?: string;
  fqdn?: string;
  netbirdIp?: string;
  netbirdIpv6?: string;
  peersTotal?: number;
  peersConnected?: number;
}
```

## `ui/src/routes/devices.$id.settings.network.tsx`

Alongside the existing `<TailscaleCard />`:

```tsx
import NetbirdCard from "@components/NetbirdCard";
// ...
<NetbirdCard />
```

## `ui/localization/messages/en.json`

Add alongside the `tailscale_*` keys. Only English is provided here -
the existing `tailscale_*` keys are translated into the other 15
languages this project ships; those translations aren't included.

```json
"netbird_connected": "Connected",
"netbird_fqdn": "FQDN",
"netbird_installed_not_running": "NetBird is installed but not running.",
"netbird_installed_not_running_state": " State: {state}",
"netbird_ipv4": "IPv4",
"netbird_ipv6": "IPv6",
"netbird_management_url_custom": "Custom",
"netbird_management_url_custom_label": "Custom Management URL",
"netbird_management_url_custom_placeholder": "https://mesh.example.com",
"netbird_management_url_default": "Default",
"netbird_management_url_description": "Configure the NetBird management server endpoint",
"netbird_management_url_title": "Management Server",
"netbird_management_url_update_failed": "Failed to update NetBird management URL: {error}",
"netbird_management_url_update_success": "NetBird management URL updated",
"netbird_needs_login": "Needs Login",
"netbird_needs_login_description": "NetBird requires authentication. Reconnect the peer with a valid setup key or complete SSO login via SSH.",
"netbird_peers": "Peers",
"netbird_refresh": "Refresh",
"netbird_save": "Save",
"netbird_saving": "Saving...",
"netbird_stopped": "Stopped",
"netbird_title": "NetBird"
```
