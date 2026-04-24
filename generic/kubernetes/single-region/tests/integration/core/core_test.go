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

	processID := "integration-test-process"
	bpmn := fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<bpmn:definitions xmlns:bpmn="http://www.omg.org/spec/BPMN/20100524/MODEL"
                  id="Definitions_1"
                  targetNamespace="http://bpmn.io/schema/bpmn">
  <bpmn:process id="%s" name="Integration Test" isExecutable="true">
    <bpmn:startEvent id="start">
      <bpmn:outgoing>toEnd</bpmn:outgoing>
    </bpmn:startEvent>
    <bpmn:endEvent id="end">
      <bpmn:incoming>toEnd</bpmn:incoming>
    </bpmn:endEvent>
    <bpmn:sequenceFlow id="toEnd" sourceRef="start" targetRef="end"/>
  </bpmn:process>
</bpmn:definitions>`, processID)

	// Write BPMN to temp file
	tmpFile, err := os.CreateTemp("", "test-process-*.bpmn")
	require.NoError(t, err)
	defer os.Remove(tmpFile.Name())
	_, err = tmpFile.WriteString(bpmn)
	require.NoError(t, err)
	tmpFile.Close()

	// Deploy via multipart form
	t.Run("Deploy", func(t *testing.T) {
		deployURL := cfg.ZeebeGatewayURL + "/v2/deployments"

		file, err := os.Open(tmpFile.Name())
		require.NoError(t, err)
		defer file.Close()

		// Build multipart request
		var b strings.Builder
		boundary := "----TestBoundary"
		b.WriteString("--" + boundary + "\r\n")
		b.WriteString("Content-Disposition: form-data; name=\"resources\"; filename=\"test-process.bpmn\"\r\n")
		b.WriteString("Content-Type: application/octet-stream\r\n\r\n")
		b.WriteString(bpmn)
		b.WriteString("\r\n--" + boundary + "--\r\n")

		req, err := http.NewRequest(http.MethodPost, deployURL, strings.NewReader(b.String()))
		require.NoError(t, err)
		req.Header.Set("Content-Type", "multipart/form-data; boundary="+boundary)
		req.Header.Set("Accept", "application/json")

		resp, err := client.Do(req)
		require.NoError(t, err)
		body, err := helpers.ReadBody(resp)
		require.NoError(t, err)
		require.Equal(t, http.StatusOK, resp.StatusCode, "deploy should succeed: %s", body)

		var result map[string]interface{}
		require.NoError(t, json.Unmarshal([]byte(body), &result))

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
				resp, err := client.Get(p.url)
				if err != nil {
					return fmt.Errorf("GET %s failed: %w", p.url, err)
				}
				body, err := helpers.ReadBody(resp)
				if err != nil {
					return err
				}
				if resp.StatusCode != http.StatusOK {
					return fmt.Errorf("expected 200, got %d", resp.StatusCode)
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
