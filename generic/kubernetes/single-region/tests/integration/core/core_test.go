// Package core implements the main integration tests for Camunda components.
// These tests replace the Venom testsuite-core.yaml.
package core

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/camunda/camunda-deployment-references/tests/integration/config"
	"github.com/camunda/camunda-deployment-references/tests/integration/helpers"
)

var (
	cfg    *config.Config
	client *helpers.Client
)

func TestMain(m *testing.M) {
	var err error
	cfg, err = config.FromEnv()
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to load config: %v\n", err)
		os.Exit(1)
	}
	client = helpers.NewClient(cfg)
	os.Exit(m.Run())
}

// TestM2MTokenGeneration verifies that machine-to-machine tokens can be obtained
// from Keycloak for each Camunda component that requires one.
func TestM2MTokenGeneration(t *testing.T) {
	if cfg.AuthMode != "oidc" {
		t.Skip("M2M token test requires OIDC auth mode")
	}

	tokenURL := cfg.KeycloakTokenURL()
	clientID := cfg.OIDCClientID
	clientSecret := cfg.OIDCSecret

	t.Run("DefaultClient", func(t *testing.T) {
		token, err := client.GetTokenForClient(tokenURL, clientID, clientSecret)
		require.NoError(t, err, "should obtain token for default client")
		assert.NotEmpty(t, token, "token should not be empty")
	})
}

// TestOrchestrationTopology checks the Zeebe cluster topology via REST API.
func TestOrchestrationTopology(t *testing.T) {
	url := cfg.ZeebeGatewayURL + "/v2/topology"

	err := helpers.Retry(cfg.RetryAttempts, cfg.RetryDelay, func() error {
		resp, err := client.Get(url)
		if err != nil {
			return fmt.Errorf("topology request failed: %w", err)
		}
		body, err := helpers.ReadBody(resp)
		if err != nil {
			return fmt.Errorf("reading body failed: %w", err)
		}
		if resp.StatusCode != http.StatusOK {
			return fmt.Errorf("expected 200, got %d: %s", resp.StatusCode, body)
		}

		var topology map[string]interface{}
		if err := json.Unmarshal([]byte(body), &topology); err != nil {
			return fmt.Errorf("invalid JSON: %w", err)
		}

		if _, ok := topology["brokers"]; !ok {
			return fmt.Errorf("topology response missing 'brokers' key")
		}
		return nil
	})
	require.NoError(t, err, "should get valid topology")
}

// TestOrchestrationProcessDefinitionSearch checks the process definition search API.
func TestOrchestrationProcessDefinitionSearch(t *testing.T) {
	url := cfg.ZeebeGatewayURL + "/v2/process-definitions/search"
	body := `{"filter":{}}`

	err := helpers.Retry(cfg.RetryAttempts, cfg.RetryDelay, func() error {
		resp, err := client.PostJSON(url, body)
		if err != nil {
			return fmt.Errorf("search request failed: %w", err)
		}
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			return fmt.Errorf("expected 200, got %d", resp.StatusCode)
		}
		return nil
	})
	require.NoError(t, err, "process definition search should succeed")
}

// TestDeployAndVerifyProcess deploys a BPMN process and verifies it's searchable.
func TestDeployAndVerifyProcess(t *testing.T) {
	if cfg.AuthMode != "oidc" && cfg.AuthMode != "basic" {
		t.Skip("process deployment requires authentication")
	}

	cases := []struct {
		name      string
		processID string
		bpmn      string
	}{
		{
			name:      "Basic",
			processID: "integration-test-process",
			bpmn:      basicProcessBPMN("integration-test-process"),
		},
		{
			// Mirrors the venom "TEST - Deploy Inbound Connector Process"
			// step. Validates that the engine accepts a BPMN that references
			// an inbound connector type (deployment-time validation only;
			// the connector worker itself is not exercised here).
			name:      "InboundConnector",
			processID: "integration-test-inbound-connector",
			bpmn:      inboundConnectorBPMN("integration-test-inbound-connector"),
		},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			deployAndVerify(t, tc.processID, tc.bpmn)
		})
	}
}

func deployAndVerify(t *testing.T, processID, bpmn string) {
	t.Helper()

	// Deploy via multipart form
	t.Run("Deploy", func(t *testing.T) {
		deployURL := cfg.ZeebeGatewayURL + "/v2/deployments"

		// Build multipart body once — it's cheap to rebuild on retry.
		var b strings.Builder
		boundary := "----TestBoundary"
		b.WriteString("--" + boundary + "\r\n")
		b.WriteString("Content-Disposition: form-data; name=\"resources\"; filename=\"test-process.bpmn\"\r\n")
		b.WriteString("Content-Type: application/octet-stream\r\n\r\n")
		b.WriteString(bpmn)
		b.WriteString("\r\n--" + boundary + "--\r\n")
		body := b.String()

		// Retry on transient 5xx (e.g. JWT JWK-set fetch timeouts when
		// Identity/Keycloak briefly hiccups between deploys — observed on
		// ROSA HCP). 4xx are returned without retry.
		var lastBody string
		var lastStatus int
		err := helpers.Retry(5, cfg.RetryDelay, func() error {
			req, err := http.NewRequest(http.MethodPost, deployURL, strings.NewReader(body))
			if err != nil {
				return err
			}
			req.Header.Set("Content-Type", "multipart/form-data; boundary="+boundary)
			req.Header.Set("Accept", "application/json")

			resp, err := client.Do(req)
			if err != nil {
				return err
			}
			respBody, err := helpers.ReadBody(resp)
			if err != nil {
				return err
			}
			lastBody = respBody
			lastStatus = resp.StatusCode
			if resp.StatusCode == http.StatusOK {
				return nil
			}
			// Only retry on transient server errors; surface 4xx immediately.
			if resp.StatusCode >= 500 {
				return fmt.Errorf("deploy returned %d: %s", resp.StatusCode, respBody)
			}
			return nil
		})
		require.NoError(t, err, "deploy should succeed after retries: %s", lastBody)
		require.Equal(t, http.StatusOK, lastStatus, "deploy should succeed: %s", lastBody)

		var result map[string]interface{}
		require.NoError(t, json.Unmarshal([]byte(lastBody), &result))

		deployments, ok := result["deployments"].([]interface{})
		require.True(t, ok, "response should have deployments array")
		require.NotEmpty(t, deployments, "deployments should not be empty")
	})

	// Verify the process is searchable
	t.Run("VerifyDeployed", func(t *testing.T) {
		searchURL := cfg.ZeebeGatewayURL + "/v2/process-definitions/search"
		searchBody := fmt.Sprintf(`{"filter":{"processDefinitionId":"%s"}}`, processID)

		err := helpers.Retry(5, cfg.RetryDelay, func() error {
			resp, err := client.PostJSON(searchURL, searchBody)
			if err != nil {
				return err
			}
			body, err := helpers.ReadBody(resp)
			if err != nil {
				return err
			}
			if resp.StatusCode != http.StatusOK {
				return fmt.Errorf("search returned %d: %s", resp.StatusCode, body)
			}

			var result struct {
				Items []struct {
					ProcessDefinitionID string `json:"processDefinitionId"`
				} `json:"items"`
			}
			if err := json.Unmarshal([]byte(body), &result); err != nil {
				return fmt.Errorf("invalid JSON: %w", err)
			}

			for _, item := range result.Items {
				if item.ProcessDefinitionID == processID {
					return nil
				}
			}
			return fmt.Errorf("process %q not found in search results", processID)
		})
		require.NoError(t, err, "deployed process should be searchable")
	})
}

// TestLoginPages checks that key Camunda web UIs return HTTP 200 and no error.
func TestLoginPages(t *testing.T) {
	if !cfg.HasDomain() {
		t.Skip("login page tests require domain/ingress")
	}

	pages := []struct {
		name string
		url  string
		skip bool
	}{
		{name: "Keycloak", url: cfg.KeycloakURL, skip: cfg.AuthMode != "oidc"},
		{name: "Console", url: cfg.ConsoleURL, skip: !cfg.ConsoleEnabled},
		{name: "Optimize", url: cfg.OptimizeURL, skip: !cfg.OptimizeEnabled},
		{name: "WebModeler", url: cfg.WebModelerURL, skip: !cfg.WebModelerEnabled},
	}

	for _, p := range pages {
		t.Run(p.name, func(t *testing.T) {
			if p.skip {
				t.Skipf("%s is not enabled", p.name)
			}

			err := helpers.Retry(cfg.RetryAttempts, cfg.RetryDelay, func() error {
				// Login pages are public; do NOT attach a bearer token. SPA
				// ingresses (e.g. WebModeler) reject M2M tokens with 401
				// because the token has no user scope.
				resp, err := client.GetUnauth(p.url)
				if err != nil {
					return fmt.Errorf("GET %s failed: %w", p.url, err)
				}
				body, err := helpers.ReadBody(resp)
				if err != nil {
					return err
				}
				// Accept 200 (page rendered) and the common redirect codes
				// (302/303/307) ingresses use to bounce unauthenticated users
				// to the IdP login flow.
				switch resp.StatusCode {
				case http.StatusOK,
					http.StatusFound,
					http.StatusSeeOther,
					http.StatusTemporaryRedirect:
				default:
					return fmt.Errorf("expected 200/3xx, got %d", resp.StatusCode)
				}
				bodyLower := strings.ToLower(body)
				if strings.Contains(bodyLower, "\"error\"") {
					return fmt.Errorf("response body contains error")
				}
				return nil
			})
			assert.NoError(t, err, "%s login page should be accessible", p.name)
		})
	}
}

// TestOrchestrationBasicAuth checks topology endpoint with basic auth.
func TestOrchestrationBasicAuth(t *testing.T) {
	if cfg.AuthMode != "basic" {
		t.Skip("basic auth test only runs in basic auth mode")
	}

	url := cfg.ZeebeGatewayURL + "/v2/topology"
	err := helpers.Retry(cfg.RetryAttempts, cfg.RetryDelay, func() error {
		resp, err := client.Get(url)
		if err != nil {
			return err
		}
		body, err := helpers.ReadBody(resp)
		if err != nil {
			return err
		}
		if resp.StatusCode != http.StatusOK {
			return fmt.Errorf("expected 200, got %d: %s", resp.StatusCode, body)
		}
		var topology map[string]interface{}
		if err := json.Unmarshal([]byte(body), &topology); err != nil {
			return fmt.Errorf("invalid JSON: %w", err)
		}
		if _, ok := topology["brokers"]; !ok {
			return fmt.Errorf("missing 'brokers' key in topology response")
		}
		return nil
	})
	require.NoError(t, err, "basic auth topology check should succeed")
}
