# Connect to an OpenVPN server

## Description

Installs the OpenVPN client if needed, connects the runner with the given
config file, and waits until the tunnel is up.

It replaces kota65535/github-openvpn-connect-action: no external
dependency, a configurable timeout, and the OpenVPN log is printed when
the connection fails. The runner is ephemeral, so there is no disconnect
step; the connection ends with the job.


## Inputs

| name | description | required | default |
| --- | --- | --- | --- |
| `config-file` | <p>Path to the OpenVPN client config file (.ovpn).</p> | `true` | `""` |
| `timeout-seconds` | <p>Maximum time to wait for the tunnel to come up.</p> | `false` | `120` |


## Runs

This action is a `composite` action.

## Usage

```yaml
- uses: camunda/camunda-deployment-references/.github/actions/internal-openvpn-connect@main
  with:
    config-file:
    # Path to the OpenVPN client config file (.ovpn).
    #
    # Required: true
    # Default: ""

    timeout-seconds:
    # Maximum time to wait for the tunnel to come up.
    #
    # Required: false
    # Default: 120
```
