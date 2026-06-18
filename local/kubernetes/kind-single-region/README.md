# Camunda 8 on Kind (Local Development)

Local Kubernetes development environment for Camunda 8 Self-Managed using Kind.

## Quick Start

**Domain mode (with TLS):**
```bash
make domain.init    # Full setup
make domain.clean   # Full cleanup
```

**No-domain mode (port-forward):**
```bash
make no-domain.init    # Full setup
make no-domain.clean   # Full cleanup
```

> **Domain mode & Keycloak:** in TLS/domain mode the Camunda pods authenticate against the public Keycloak issuer (`https://camunda.example.com/auth/...`), which only becomes reachable a few minutes after install while DNS, the TLS certificate and the `camunda-platform` realm converge. `domain.init` runs `wait-for-keycloak.sh` automatically to block until the issuer answers and then restart the app pods, so a transient `CrashLoopBackOff` on first start clears on its own.

## Further Instructions

For detailed setup instructions and additional options, see:
- Run `make help` for all available commands
- Official documentation: https://docs.camunda.io/docs/self-managed/deployment/helm/cloud-providers/kind/
