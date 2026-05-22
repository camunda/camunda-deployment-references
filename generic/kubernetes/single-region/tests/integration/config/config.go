// Package config provides configuration for Camunda integration tests.
// Configuration is loaded from environment variables.
package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

// Config holds all test configuration loaded from environment variables.
type Config struct {
	// Cluster access
	Namespace   string
	ReleaseName string
	ClusterType string // "kubernetes" or "openshift"

	// Domain / Ingress
	Domain     string // empty = no-domain mode (use port-forward)
	DomainGRPC string

	// Auth
	AuthMode     string // "oidc", "basic", "none"
	BasicUser    string
	BasicPass    string
	OIDCTokenURL string
	OIDCClientID string
	OIDCSecret   string

	// Component toggles
	ElasticsearchEnabled bool
	WebModelerEnabled    bool
	ConsoleEnabled       bool
	OptimizeEnabled      bool

	// Service addresses (populated from env or derived)
	ZeebeGatewayURL  string // e.g. http://localhost:8080
	KeycloakURL      string // e.g. http://localhost:18080/auth
	ElasticsearchURL string // e.g. http://localhost:9200
	// Optional Elasticsearch HTTP basic auth (used by preflight probes when
	// the cluster is deployed with security enabled, e.g. ECK operator).
	ElasticsearchUser     string
	ElasticsearchPassword string
	OrchestrationURL      string // internal orchestration URL
	ConnectorsURL         string
	IdentityURL           string
	ConsoleURL            string
	OptimizeURL           string
	WebModelerURL         string

	// Timeouts
	HTTPTimeout   time.Duration
	RetryAttempts int
	RetryDelay    time.Duration
}

// FromEnv creates a Config by reading environment variables.
func FromEnv() (*Config, error) {
	c := &Config{
		Namespace:   envOr("TEST_NAMESPACE", "camunda"),
		ReleaseName: envOr("TEST_RELEASE_NAME", "camunda"),
		ClusterType: envOr("TEST_CLUSTER_TYPE", "kubernetes"),

		Domain:     envOr("CAMUNDA_DOMAIN", ""),
		DomainGRPC: envOr("CAMUNDA_DOMAIN_GRPC", ""),

		AuthMode:     envOr("TEST_AUTH_MODE", "oidc"),
		BasicUser:    envOr("TEST_BASIC_USER", ""),
		BasicPass:    envOr("TEST_BASIC_PASSWORD", ""),
		OIDCTokenURL: envOr("TEST_OIDC_TOKEN_URL", ""),
		OIDCClientID: envOr("TEST_OIDC_CLIENT_ID", ""),
		OIDCSecret:   envOr("TEST_OIDC_CLIENT_SECRET", ""),

		ElasticsearchEnabled: envBool("ELASTICSEARCH_ENABLED", true),
		WebModelerEnabled:    envBool("WEBMODELER_ENABLED", false),
		ConsoleEnabled:       envBool("CONSOLE_ENABLED", false),
		OptimizeEnabled:      envBool("OPTIMIZE_ENABLED", true),

		ElasticsearchUser:     envOr("TEST_ELASTICSEARCH_USER", ""),
		ElasticsearchPassword: envOr("TEST_ELASTICSEARCH_PASSWORD", ""),

		HTTPTimeout:   envDuration("TEST_HTTP_TIMEOUT", 30*time.Second),
		RetryAttempts: envInt("TEST_RETRY_ATTEMPTS", 3),
		RetryDelay:    envDuration("TEST_RETRY_DELAY", 10*time.Second),
	}

	c.setServiceURLs()
	return c, nil
}

func (c *Config) setServiceURLs() {
	if c.Domain != "" {
		base := fmt.Sprintf("https://%s", c.Domain)
		c.ZeebeGatewayURL = base
		c.KeycloakURL = base + "/auth"
		// Actuator endpoints (/actuator/health/...) are NOT exposed via the
		// public ingress; they live on internal management ports. Allow the
		// caller to override Orchestration/Connectors URLs (typically with
		// localhost port-forwards) so preflight checks can still run.
		c.OrchestrationURL = envOr("TEST_ORCHESTRATION_URL", base)
		c.ConnectorsURL = envOr("TEST_CONNECTORS_URL", base+"/connectors")
		c.IdentityURL = envOr("TEST_IDENTITY_URL", base+"/identity")
		c.ConsoleURL = envOr("TEST_CONSOLE_URL", base+"/console")
		c.OptimizeURL = envOr("TEST_OPTIMIZE_URL", base+"/optimize")
		c.WebModelerURL = envOr("TEST_WEBMODELER_URL", base+"/modeler")
		// Elasticsearch is never exposed via the public ingress, so always
		// require a port-forwarded URL (defaults to localhost:9200).
		c.ElasticsearchURL = envOr("TEST_ELASTICSEARCH_URL", "http://localhost:9200")
	} else {
		// Port-forward mode: services at localhost
		c.ZeebeGatewayURL = envOr("TEST_ZEEBE_GATEWAY_URL", "http://localhost:8080")
		c.KeycloakURL = envOr("TEST_KEYCLOAK_URL", "http://localhost:18080/auth")
		c.ElasticsearchURL = envOr("TEST_ELASTICSEARCH_URL", "http://localhost:9200")

		// Internal service URLs (via port-forward or in-cluster)
		rel := c.ReleaseName
		c.OrchestrationURL = envOr("TEST_ORCHESTRATION_URL", fmt.Sprintf("http://localhost:9600"))
		c.ConnectorsURL = envOr("TEST_CONNECTORS_URL", fmt.Sprintf("http://%s-connectors:8080", rel))
		c.IdentityURL = envOr("TEST_IDENTITY_URL", fmt.Sprintf("http://%s-identity:8080", rel))
		c.ConsoleURL = envOr("TEST_CONSOLE_URL", fmt.Sprintf("http://%s-console:8080", rel))
		c.OptimizeURL = envOr("TEST_OPTIMIZE_URL", fmt.Sprintf("http://%s-optimize:8083", rel))
		c.WebModelerURL = envOr("TEST_WEBMODELER_URL", fmt.Sprintf("http://%s-web-modeler-webapp:8070", rel))
	}
}

// HasDomain returns true if a domain (ingress) is configured.
func (c *Config) HasDomain() bool {
	return c.Domain != ""
}

// KeycloakTokenURL returns the full token endpoint URL.
func (c *Config) KeycloakTokenURL() string {
	if c.OIDCTokenURL != "" {
		return c.OIDCTokenURL
	}
	return c.KeycloakURL + "/realms/camunda-platform/protocol/openid-connect/token"
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envBool(key string, def bool) bool {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	return strings.EqualFold(v, "true") || v == "1"
}

func envInt(key string, def int) int {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return def
	}
	return n
}

func envDuration(key string, def time.Duration) time.Duration {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		return def
	}
	return d
}
