package core

import (
	"encoding/json"
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestM2MTokenPerComponent validates that a client_credentials token can be
// obtained for each Camunda component client individually. Mirrors the venom
// "TEST - Generating M2M Token" suite that iterated over connectors / optimize
// / orchestration clients.
//
// The set of components is provided via the TEST_OIDC_M2M_CLIENTS env var as
// a JSON object: {"connectors":"<secret>","optimize":"<secret>", ...}
// The map key is used as the OIDC client_id.
func TestM2MTokenPerComponent(t *testing.T) {
	if cfg.AuthMode != "oidc" {
		t.Skip("M2M token test requires OIDC auth mode")
	}

	raw := os.Getenv("TEST_OIDC_M2M_CLIENTS")
	if raw == "" {
		t.Skip("TEST_OIDC_M2M_CLIENTS not set; skipping per-component M2M check")
	}

	var clients map[string]string
	require.NoError(t, json.Unmarshal([]byte(raw), &clients), "TEST_OIDC_M2M_CLIENTS must be a valid JSON object")
	require.NotEmpty(t, clients, "no M2M clients to test")

	tokenURL := cfg.KeycloakTokenURL()
	for clientID, secret := range clients {
		clientID, secret := clientID, secret
		t.Run(clientID, func(t *testing.T) {
			if secret == "" {
				t.Skipf("no secret provided for client %q", clientID)
			}
			token, err := client.GetTokenForClient(tokenURL, clientID, secret)
			require.NoError(t, err, "should obtain token for client %q", clientID)
			assert.NotEmpty(t, token, "token for client %q should not be empty", clientID)
		})
	}
}
