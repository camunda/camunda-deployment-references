package core

import (
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"

	"github.com/camunda/camunda-deployment-references/tests/integration/helpers"
)

// componentReadyTimeout bounds how long the component reachability probes keep
// retrying a transient 5xx. Satellite components (reached via the ingress) can
// briefly return 5xx while they finish starting — even after their readiness
// probe is green — until the orchestration's domain-mode OIDC startup settles.
// (Observed: Identity's /api/users returned 500 for ~45s on a ROSA HCP domain
// run.) Bounded so a component that stays unreachable past it still fails.
const componentReadyTimeout = 3 * time.Minute

// TestComponentAPIs verifies the authenticated API endpoints exposed by the
// satellite components (Console, Identity, Connectors). Mirrors the venom
// "TEST - Interacting with Web API" suite.
//
// Each sub-test is skipped when the corresponding component is disabled or
// when the URL is unreachable from the runner (typically no-domain mode where
// no port-forward was set up for that component).
func TestComponentAPIs(t *testing.T) {
	if cfg.AuthMode != "oidc" && cfg.AuthMode != "basic" {
		t.Skip("component API tests require authentication")
	}

	cases := []struct {
		name        string
		url         string
		path        string
		acceptCodes []int
		skip        bool
		skipReason  string
	}{
		{
			name: "Console",
			url:  cfg.ConsoleURL,
			path: "/api/clusters",
			// Console SPA expects session-cookie auth; bearer M2M tokens get
			// rejected with 401. 401 still proves the endpoint is reachable
			// & enforcing auth, which mirrors what venom validated.
			acceptCodes: []int{http.StatusOK, http.StatusUnauthorized},
			// Console is only exposed via ingress; in port-forward / no-domain
			// mode the default URL points to the in-cluster service DNS which
			// is unreachable from the runner.
			skip:       !cfg.ConsoleEnabled || !cfg.HasDomain(),
			skipReason: "Console disabled or not reachable without ingress",
		},
		{
			name: "Identity",
			url:  cfg.IdentityURL,
			path: "/api/users",
			// Identity may answer 200 (admin) or 403 (M2M client without
			// admin scope). 403 still proves the API is reachable & enforcing
			// auth, which is what venom validated.
			acceptCodes: []int{http.StatusOK, http.StatusForbidden},
			skip:        !cfg.HasDomain(),
			skipReason:  "Identity not reachable without ingress",
		},
		{
			name: "Connectors",
			url:  cfg.ConnectorsURL,
			// /actuator/health is the canonical Spring Boot reachability probe;
			// /actuator/info can return 500 when an InfoContributor fails even
			// though the app itself is up.
			path:        "/actuator/health",
			acceptCodes: []int{http.StatusOK, http.StatusServiceUnavailable},
		},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			if tc.skip {
				t.Skip(tc.skipReason)
			}
			if tc.url == "" {
				t.Skipf("%s URL not configured", tc.name)
			}
			fullURL := tc.url + tc.path
			// These are reachability probes, so allow a longer bounded warm-up
			// than the short per-request cfg.RetryAttempts to absorb a
			// component's transient startup 5xx (see componentReadyTimeout).
			readyAttempts := cfg.RetryAttempts
			if cfg.RetryDelay > 0 {
				if want := int(componentReadyTimeout/cfg.RetryDelay) + 1; readyAttempts < want {
					readyAttempts = want
				}
			}
			err := helpers.Retry(readyAttempts, cfg.RetryDelay, func() error {
				resp, err := client.Get(fullURL)
				if err != nil {
					return fmt.Errorf("GET %s failed: %w", fullURL, err)
				}
				defer resp.Body.Close()
				for _, c := range tc.acceptCodes {
					if resp.StatusCode == c {
						return nil
					}
				}
				return fmt.Errorf("GET %s: unexpected status %d (accepted: %v)", fullURL, resp.StatusCode, tc.acceptCodes)
			})
			assert.NoError(t, err, "%s API endpoint %s should be reachable", tc.name, tc.path)
		})
	}
}
