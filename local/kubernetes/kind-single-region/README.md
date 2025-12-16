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

## Further Instructions

For detailed setup instructions and additional options, see:
- Run `make help` for all available commands
- Official documentation: https://docs.camunda.io/docs/self-managed/deployment/helm/cloud-providers/kind/
