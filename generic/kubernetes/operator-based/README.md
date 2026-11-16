# Camunda Infrastructure with Kubernetes Operators

This guide documents the installation of Camunda infrastructure components using Kubernetes operators. All required files are provided in this directory for easy deployment.

[Documentation of the installation procedure](https://docs.camunda.io/docs/self-managed/deployment/helm/configure/vendor-supported-infrastructure/)

## Keycloak 26.8.2 and later: grant `kc-admin-api` to Management Identity

Keycloak 26.8.2 fixes CVE-2026-19688: the Admin REST API only accepts tokens that carry the `kc-admin-api` client scope. Management Identity calls that API with its own `camunda-identity` client, which does not get the scope, so without the step below Identity stops at startup with `HTTP status code: 401` and goes into CrashLoopBackOff ([camunda/camunda#69230](https://github.com/camunda/camunda/issues/69230)).

When Camunda uses the operator-managed Keycloak from this directory, run this after the Camunda Helm install (for example after `generic/kubernetes/single-region/procedure/install-chart.sh` or `generic/openshift/single-region/procedure/install-chart.sh`), from this directory:

```bash
./keycloak/keycloak-grant-identity-admin-api.sh
```

It waits for Identity to create its client, assigns `kc-admin-api` to it as a default client scope, and restarts Identity. It is idempotent, does nothing on a Keycloak without the check, and only warns (exit 0) if it cannot finish within `KEYCLOAK_ADMIN_API_TIMEOUT_SECONDS` (default 600). The defaults match this directory (namespace and release `camunda`, pod `keycloak-0`, realm `camunda-platform`); see the script header for the variables that override them. Use `KUBECTL=oc` on OpenShift if `kubectl` is not installed. With an external OIDC provider instead of this Keycloak, skip it.

Remove this step once the Identity release in use assigns the scope itself.
