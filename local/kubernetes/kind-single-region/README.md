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

> **Domain mode & Keycloak:** in TLS/domain mode the Camunda pods authenticate against the public Keycloak issuer (`https://camunda.example.com/auth/...`), which only becomes reachable a few minutes after install while DNS, the TLS certificate and the `camunda-platform` realm converge. `domain.init` runs `wait-for-keycloak.sh` automatically: it waits (up to a timeout) for the issuer, then restarts the app pods so a transient first-start `CrashLoopBackOff` clears quickly. If the issuer is slower than the timeout the script warns and continues, and the pods recover on their own once it converges.

## Further Instructions

For detailed setup instructions and additional options, see:
- Run `make help` for all available commands
- Official documentation: https://docs.camunda.io/docs/self-managed/deployment/helm/cloud-providers/kind/
