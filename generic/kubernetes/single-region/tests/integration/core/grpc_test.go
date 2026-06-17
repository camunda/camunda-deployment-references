package core

import (
	"crypto/tls"
	"net"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
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
	conn, err := tls.DialWithDialer(dialer, "tcp", addr, &tls.Config{
		ServerName: host,
		MinVersion: tls.VersionTLS12,
		NextProtos: []string{"h2"},
	})
	require.NoError(t, err, "TLS dial to %s should succeed", addr)
	defer conn.Close()

	state := conn.ConnectionState()
	assert.Equal(t, "h2", state.NegotiatedProtocol,
		"gRPC requires HTTP/2: ingress must negotiate ALPN h2 (got %q)", state.NegotiatedProtocol)
}
