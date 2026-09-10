// Meant to live at the root of jetkvm/kvm (package kvm), alongside
// tailscale.go, which it mirrors. Depends on that repo's own config.go
// (NetbirdManagementURL field, ensureConfigLoaded, SaveConfig) and
// log.go (netbirdLogger) - not buildable standalone, unlike
// internal/netbird itself.
package kvm

import (
	"fmt"

	"github.com/jtbrough/jetkvm-netbird/internal/netbird"
)

func rpcGetNetbirdStatus() (*netbird.Status, error) {
	ensureConfigLoaded()
	return netbird.GetStatus(func(err error) {
		netbirdLogger.Warn().Err(err).Msg("failed to get netbird status")
	})
}

func rpcGetNetbirdManagementURL() (string, error) {
	ensureConfigLoaded()
	return netbird.EffectiveManagementURL(config.NetbirdManagementURL), nil
}

func rpcSetNetbirdManagementURL(managementURL string) error {
	ensureConfigLoaded()

	previousURL := config.NetbirdManagementURL

	normalized, err := netbird.SetManagementURL(managementURL)
	if err != nil {
		return err
	}

	config.NetbirdManagementURL = normalized
	if err := SaveConfig(); err != nil {
		config.NetbirdManagementURL = previousURL
		return fmt.Errorf("failed to save netbird management URL: %w", err)
	}

	return nil
}
