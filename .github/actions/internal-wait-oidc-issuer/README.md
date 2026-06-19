# Wait for the OIDC issuer to be reachable

## Description

CI-only helper for domain / TLS test runs.

In domain mode the Camunda app pods (orchestration / Zeebe and Connectors)
fetch the OIDC discovery document from the configured issuer at startup. On a
freshly provisioned cluster that issuer only converges minutes after
`helm install` — DNS, the TLS certificate and the ingress have to settle, and
a self-hosted IdP also has to provision its realm — during which the app pods
`CrashLoopBackOff`. Their exponential restart backoff can outlast the
readiness window, so the deployment can look broken for a while.

This action waits (bounded, fail-open) for the issuer's discovery document to
answer `200`, then bounces the affected workloads so they restart immediately
instead of after the next backoff window.

It is **IdP-agnostic**: it polls whatever `issuer-url` the caller provides and
is a quick no-op for an already-reachable issuer (e.g. an external IdP). It is
deliberately a CI-only composite action — the customer-facing reference
procedures stay free of this environment-specific workaround.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `issuer-url` | <p>OIDC issuer base URL. The discovery document polled is <code>&lt;issuer-url&gt;/.well-known/openid-configuration</code>.</p> | `true` | `""` |
| `namespace` | <p>Kubernetes namespace of the deployed release.</p> | `false` | `camunda` |
| `release-name` | <p>Helm release name, used to target the workloads to bounce (<code>statefulset/&lt;release&gt;-zeebe</code>, <code>deployment/&lt;release&gt;-connectors</code>).</p> | `false` | `camunda` |
| `insecure` | <p>Set to 'true' to skip TLS verification of the issuer (e.g. when the public endpoint uses a CI internal-CA / Vault wildcard certificate).</p> | `false` | `""` |
| `timeout-seconds` | <p>Total wall-clock budget in seconds. Fail-open: on timeout the action emits a warning and exits 0 so it never blocks the pipeline.</p> | `false` | `600` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: ***PROJECT***@***VERSION***
  with:
    issuer-url:
    # OIDC issuer base URL. The discovery document polled is
    # `<issuer-url>/.well-known/openid-configuration`.
    #
    # Required: true
    # Default: ""

    namespace:
    # Kubernetes namespace of the deployed release.
    #
    # Required: false
    # Default: camunda

    release-name:
    # Helm release name, used to target the workloads to bounce
    # (`statefulset/<release>-zeebe`, `deployment/<release>-connectors`).
    #
    # Required: false
    # Default: camunda

    insecure:
    # Set to 'true' to skip TLS verification of the issuer (e.g. when the
    # public endpoint uses a CI internal-CA / Vault wildcard certificate).
    #
    # Required: false
    # Default: ""

    timeout-seconds:
    # Total wall-clock budget in seconds. Fail-open: on timeout the action
    # emits a warning and exits 0 so it never blocks the pipeline.
    #
    # Required: false
    # Default: 600
```
