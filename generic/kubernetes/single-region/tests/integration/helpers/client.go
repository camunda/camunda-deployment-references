// Package helpers provides HTTP client, auth, and retry utilities for Camunda integration tests.
package helpers

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/camunda/camunda-deployment-references/tests/integration/config"
)

// Client wraps an HTTP client with authentication support.
type Client struct {
	http    *http.Client
	cfg     *config.Config
	tokenFn func() (string, error)
	token   string
	tokenAt time.Time
}

// NewClient creates an authenticated HTTP client from config.
func NewClient(cfg *config.Config) *Client {
	transport := &http.Transport{
		TLSClientConfig: &tls.Config{MinVersion: tls.VersionTLS12},
	}
	c := &Client{
		http: &http.Client{
			Timeout:   cfg.HTTPTimeout,
			Transport: transport,
		},
		cfg: cfg,
	}
	if cfg.AuthMode == "oidc" {
		c.tokenFn = c.fetchOIDCToken
	}
	return c
}

func (c *Client) fetchOIDCToken() (string, error) {
	data := url.Values{
		"grant_type":    {"client_credentials"},
		"client_id":     {c.cfg.OIDCClientID},
		"client_secret": {c.cfg.OIDCSecret},
	}
	resp, err := c.http.Post(c.cfg.KeycloakTokenURL(), "application/x-www-form-urlencoded", strings.NewReader(data.Encode()))
	if err != nil {
		return "", fmt.Errorf("token request failed: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("token endpoint returned %d: %s", resp.StatusCode, string(body))
	}
	var result struct {
		AccessToken string `json:"access_token"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", fmt.Errorf("failed to decode token response: %w", err)
	}
	if result.AccessToken == "" {
		return "", fmt.Errorf("empty access_token in response")
	}
	return result.AccessToken, nil
}

func (c *Client) getToken() (string, error) {
	if c.tokenFn == nil {
		return "", nil
	}
	if c.token != "" && time.Since(c.tokenAt) < 4*time.Minute {
		return c.token, nil
	}
	t, err := c.tokenFn()
	if err != nil {
		return "", err
	}
	c.token = t
	c.tokenAt = time.Now()
	return t, nil
}

// Do executes an HTTP request with authentication.
func (c *Client) Do(req *http.Request) (*http.Response, error) {
	switch c.cfg.AuthMode {
	case "basic":
		req.SetBasicAuth(c.cfg.BasicUser, c.cfg.BasicPass)
	case "oidc":
		token, err := c.getToken()
		if err != nil {
			return nil, fmt.Errorf("auth failed: %w", err)
		}
		req.Header.Set("Authorization", "Bearer "+token)
	}
	return c.http.Do(req)
}

// Get performs a GET request.
func (c *Client) Get(url string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	return c.Do(req)
}

// GetUnauth performs a GET request without injecting any authentication
// header. Useful for public endpoints (e.g. login pages) where attaching a
// stale or M2M bearer triggers a 401 from SPA-style ingresses.
func (c *Client) GetUnauth(url string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	return c.http.Do(req)
}

// PostJSON performs a POST request with a JSON body.
func (c *Client) PostJSON(url string, body string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(context.Background(), http.MethodPost, url, strings.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	return c.Do(req)
}

// GetTokenForClient fetches an OIDC token for a specific client_id/client_secret pair.
func (c *Client) GetTokenForClient(tokenURL, clientID, clientSecret string) (string, error) {
	data := url.Values{
		"grant_type":    {"client_credentials"},
		"client_id":     {clientID},
		"client_secret": {clientSecret},
	}
	resp, err := c.http.Post(tokenURL, "application/x-www-form-urlencoded", strings.NewReader(data.Encode()))
	if err != nil {
		return "", fmt.Errorf("token request failed: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("token endpoint returned %d: %s", resp.StatusCode, string(body))
	}
	var result struct {
		AccessToken string `json:"access_token"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", fmt.Errorf("decode failed: %w", err)
	}
	return result.AccessToken, nil
}

// Retry executes fn up to maxAttempts times with the given delay between attempts.
func Retry(maxAttempts int, delay time.Duration, fn func() error) error {
	var lastErr error
	for i := 0; i < maxAttempts; i++ {
		if err := fn(); err != nil {
			lastErr = err
			if i < maxAttempts-1 {
				time.Sleep(delay)
			}
			continue
		}
		return nil
	}
	return fmt.Errorf("failed after %d attempts: %w", maxAttempts, lastErr)
}

// ReadBody reads the response body and closes it.
func ReadBody(resp *http.Response) (string, error) {
	defer resp.Body.Close()
	b, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	return string(b), nil
}
