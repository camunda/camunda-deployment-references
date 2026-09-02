package core

import (
	"crypto/tls"
	"fmt"
	"net"
	"strings"
	"testing"
	"time"

	"github.com/camunda/camunda-deployment-references/tests/integration/helpers"
	"github.com/stretchr/testify/require"
)

// TestOrchestrationGRPC validates that the Zeebe gateway gRPC endpoint is
// reachable over TLS and negotiates HTTP/2 (the transport gRPC requires).
// Mirrors the venom "TEST - Orchestration Keycloak Auth" sub-step that ran
// `zbctl status` over gRPC.
//
// We deliberately avoid pulling in a full Zeebe gRPC client to keep this
// module dependency-free; verifying the TLS+ALPN handshake catches the same
// class of regressions (ingress wiring, certificate, port exposure) that
// `zbctl status` did, without exercising Zeebe internals already covered by
// the REST topology test.
func TestOrchestrationGRPC(t *testing.T) {
	if cfg.DomainGRPC == "" {
		t.Skip("CAMUNDA_DOMAIN_GRPC not set; skipping gRPC connectivity check")
	}

	addr := cfg.DomainGRPC
	if !strings.Contains(addr, ":") {
		addr += ":443"
	}
	host := addr
	if h, _, err := net.SplitHostPort(addr); err == nil {
		host = h
	}

	dialer := &net.Dialer{Timeout: 10 * time.Second}

	// Retry the dial + ALPN handshake: right after deployment the public gRPC
	// hostname may not resolve yet (external-DNS / ingress propagation lag),
	// which otherwise fails the very first attempt with "no such host". Mirror
	// the retry/warmup the REST topology test already uses.
	err := helpers.Retry(cfg.RetryAttempts, cfg.RetryDelay, func() error {
		conn, err := tls.DialWithDialer(dialer, "tcp", addr, &tls.Config{
			ServerName: host,
			MinVersion: tls.VersionTLS12,
			NextProtos: []string{"h2"},
		})
		if err != nil {
			return fmt.Errorf("TLS dial to %s failed: %w", addr, err)
		}
		defer conn.Close()

		if proto := conn.ConnectionState().NegotiatedProtocol; proto != "h2" {
			return fmt.Errorf("gRPC requires HTTP/2: ingress must negotiate ALPN h2 (got %q)", proto)
		}
		return nil
	})
	require.NoError(t, err, "gRPC endpoint %s should be reachable over TLS negotiating ALPN h2", addr)
}
