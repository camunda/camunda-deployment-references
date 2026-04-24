// Package preflight implements readiness and liveness checks for Camunda components.
// These tests replace the Venom testsuite-preflight.yaml.
package preflight

import (
	"fmt"
	"net/http"
	"os"
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

// TestElasticsearchReadiness checks that Elasticsearch cluster is reachable.
func TestElasticsearchReadiness(t *testing.T) {
	if !cfg.ElasticsearchEnabled {
		t.Skip("Elasticsearch is not enabled")
	}
	url := cfg.ElasticsearchURL + "/_cluster/health?timeout=1s"
	err := helpers.Retry(cfg.RetryAttempts, cfg.RetryDelay, func() error {
		resp, err := client.Get(url)
		if err != nil {
			return fmt.Errorf("request failed: %w", err)
		}
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			return fmt.Errorf("expected 200, got %d", resp.StatusCode)
		}
		return nil
	})
	assert.NoError(t, err, "Elasticsearch should be ready")
}

// TestElasticsearchLiveness checks Elasticsearch cluster status is green.
func TestElasticsearchLiveness(t *testing.T) {
	if !cfg.ElasticsearchEnabled {
		t.Skip("Elasticsearch is not enabled")
	}
	url := cfg.ElasticsearchURL + "/_cluster/health?wait_for_status=green&timeout=1s"
	err := helpers.Retry(cfg.RetryAttempts, cfg.RetryDelay, func() error {
		resp, err := client.Get(url)
		if err != nil {
			return fmt.Errorf("request failed: %w", err)
		}
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			return fmt.Errorf("expected 200, got %d", resp.StatusCode)
		}
		return nil
	})
	assert.NoError(t, err, "Elasticsearch cluster should be green")
}

// Component represents a Camunda component to health-check.
type Component struct {
	Name string
	URL  string
}

func healthComponents() []Component {
	components := []Component{
		{Name: "Orchestration", URL: cfg.OrchestrationURL},
	}
	if cfg.ConnectorsURL != "" {
		components = append(components, Component{Name: "Connectors", URL: cfg.ConnectorsURL})
	}
	return components
}

// TestReadiness checks /actuator/health/readiness for each component.
func TestReadiness(t *testing.T) {
	for _, comp := range healthComponents() {
		t.Run(comp.Name, func(t *testing.T) {
			url := comp.URL + "/actuator/health/readiness"
			err := helpers.Retry(cfg.RetryAttempts, cfg.RetryDelay, func() error {
				resp, err := client.Get(url)
				if err != nil {
					return fmt.Errorf("request to %s failed: %w", url, err)
				}
				defer resp.Body.Close()
				if resp.StatusCode != http.StatusOK {
					return fmt.Errorf("%s readiness: expected 200, got %d", comp.Name, resp.StatusCode)
				}
				return nil
			})
			require.NoError(t, err, "%s should be ready", comp.Name)
		})
	}
}

// TestLiveness checks /actuator/health/liveness for each component.
func TestLiveness(t *testing.T) {
	for _, comp := range healthComponents() {
		t.Run(comp.Name, func(t *testing.T) {
			url := comp.URL + "/actuator/health/liveness"
			err := helpers.Retry(cfg.RetryAttempts, cfg.RetryDelay, func() error {
				resp, err := client.Get(url)
				if err != nil {
					return fmt.Errorf("request to %s failed: %w", url, err)
				}
				defer resp.Body.Close()
				if resp.StatusCode != http.StatusOK {
					return fmt.Errorf("%s liveness: expected 200, got %d", comp.Name, resp.StatusCode)
				}
				return nil
			})
			require.NoError(t, err, "%s should be alive", comp.Name)
		})
	}
}
