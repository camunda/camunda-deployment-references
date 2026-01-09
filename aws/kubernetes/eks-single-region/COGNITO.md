# Amazon Cognito Integration for EKS Single Region

This document describes how to use Amazon Cognito as the identity provider for Camunda Platform on AWS EKS, replacing the default embedded Keycloak.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           AWS                                    │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   Amazon Cognito                          │   │
│  │  ┌────────────────────────────────────────────────────┐  │   │
│  │  │              User Pool: camunda                     │  │   │
│  │  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐   │  │   │
│  │  │  │Identity │ │Optimize │ │Orchestr.│ │Connectors│  │  │   │
│  │  │  │ Client  │ │ Client  │ │ Client  │ │ Client  │   │  │   │
│  │  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘   │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              │ OAuth2/OIDC                       │
│                              ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                  AWS Secrets Manager                      │   │
│  │  ┌────────────────────────────────────────────────────┐  │   │
│  │  │  {cluster}/camunda/cognito                         │  │   │
│  │  │  - user_pool_id, issuer_url, jwks_url              │  │   │
│  │  │  - identity_client_id / identity_client_secret     │  │   │
│  │  │  - optimize_client_id / optimize_client_secret     │  │   │
│  │  │  - ...                                             │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                     Amazon EKS                            │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐        │   │
│  │  │Identity │ │Optimize │ │ Operate │ │Connectors│        │   │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘        │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Why Cognito instead of Keycloak?

| Feature | Keycloak | Amazon Cognito |
|---------|----------|----------------|
| **Management** | Self-managed | Fully managed by AWS |
| **Database** | Requires PostgreSQL | Built-in storage |
| **Scaling** | Manual HA setup | Auto-scaling |
| **Cost** | Compute + Storage + Maintenance | Pay per MAU |
| **Integration** | Generic OIDC | Native AWS (IAM, CloudWatch, WAF) |
| **MFA** | Manual configuration | Built-in, one-click |
| **Federation** | SAML/OIDC setup | Native social + enterprise IdP |
| **Secret Storage** | Kubernetes Secrets | AWS Secrets Manager |

## Prerequisites

1. **AWS CLI** configured with access to your EKS cluster
2. **Terraform** >= 1.0
3. **jq** for JSON parsing
4. **kubectl** configured for your EKS cluster

## Configuration

### 1. Enable Cognito in Terraform

Create or update `terraform.tfvars`:

```hcl
# Enable Amazon Cognito authentication
enable_cognito = true

# Domain name for your Camunda deployment
domain_name = "camunda.example.com"

# Initial admin user email
identity_initial_user_email = "admin@example.com"

# Enable MFA (optional but recommended)
cognito_mfa_enabled = true

# Create initial admin user
cognito_create_admin_user = true

# Optional components
enable_console    = true
enable_webmodeler = true
```

### 2. Apply Terraform

```bash
cd terraform/cluster

terraform init
terraform apply
```

This creates:
- Cognito User Pool with password policy and MFA
- App Clients for each Camunda component
- Resource Server with custom scopes
- Initial admin user (if enabled)
- AWS Secrets Manager secret with all credentials
- IAM policy for secret access

### 3. Export Cognito Configuration

```bash
source procedure/vars-cognito.sh
```

### 4. Create Kubernetes Secrets

```bash
export CAMUNDA_NAMESPACE=camunda
./procedure/create-cognito-secrets.sh
```

### 5. Install Camunda with Cognito Helm Values

```bash
# Export other required variables (database, etc.)
source procedure/vars-create-db.sh

# Install with Cognito values
helm install camunda camunda/camunda-platform \
  -n $CAMUNDA_NAMESPACE \
  -f helm-values/values-cognito.yml
```

## Cognito Resources Created

### User Pool
- Name: `{cluster}-camunda`
- Username: Email-based
- Password policy: 12+ chars, mixed case, numbers, symbols
- MFA: Optional (configurable)
- Account recovery: Email-based

### App Clients

| Client | Type | Secret | Purpose |
|--------|------|--------|---------|
| `{prefix}-identity` | Confidential | Yes | Central authentication |
| `{prefix}-optimize` | Confidential | Yes | Process analytics |
| `{prefix}-orchestration` | Confidential | Yes | Operate/Tasklist/Zeebe |
| `{prefix}-console` | Public (SPA) | No | Management UI |
| `{prefix}-connectors` | Confidential | Yes | Connectors service |
| `{prefix}-webmodeler-ui` | Public (SPA) | No | Modeler frontend |
| `{prefix}-webmodeler-api` | Confidential | Yes | Modeler backend |

### OIDC Endpoints

All endpoints are automatically configured:
- **Issuer**: `https://cognito-idp.{region}.amazonaws.com/{pool_id}`
- **JWKS**: `{issuer}/.well-known/jwks.json`
- **Token**: `https://{domain}.auth.{region}.amazoncognito.com/oauth2/token`
- **Authorize**: `https://{domain}.auth.{region}.amazoncognito.com/oauth2/authorize`

## User Management

### Add Users via AWS Console
1. Go to Amazon Cognito → User Pools → `{cluster}-camunda`
2. Click "Create user"
3. Enter email and set temporary password

### Add Users via CLI
```bash
aws cognito-idp admin-create-user \
  --user-pool-id $COGNITO_USER_POOL_ID \
  --username user@example.com \
  --user-attributes Name=email,Value=user@example.com Name=email_verified,Value=true \
  --temporary-password "TempP@ss123!"
```

### List Users
```bash
aws cognito-idp list-users --user-pool-id $COGNITO_USER_POOL_ID
```

## Federation with External IdPs

Cognito supports federation with:
- **Social**: Google, Facebook, Amazon, Apple
- **Enterprise**: SAML 2.0, OIDC

To add an external IdP:
1. Go to Cognito → User Pools → Federation
2. Add identity provider
3. Configure attribute mapping

## Troubleshooting

### "Invalid redirect_uri"
Ensure the callback URLs in Cognito match exactly:
1. Go to Cognito → User Pools → App clients
2. Check "Allowed callback URLs"
3. URLs must match exactly (including trailing slashes for SPAs)

### "Access token expired"
Token validity is set to 1 hour by default. For longer sessions:
1. Go to Cognito → User Pools → App clients
2. Increase "Access token expiration"

### User can't login
1. Check user status: `aws cognito-idp admin-get-user --user-pool-id $COGNITO_USER_POOL_ID --username user@example.com`
2. If status is FORCE_CHANGE_PASSWORD, user needs to set new password
3. Reset password: `aws cognito-idp admin-set-user-password --user-pool-id $COGNITO_USER_POOL_ID --username user@example.com --password "NewP@ss123!" --permanent`

## Security Best Practices

1. **Enable MFA**: Set `cognito_mfa_enabled = true`
2. **Use strong passwords**: Default policy requires 12+ chars
3. **Enable Advanced Security**: Automatically enabled in AUDIT mode
4. **Monitor with CloudWatch**: Cognito logs authentication events
5. **Use AWS WAF**: Protect Cognito endpoints from abuse
6. **Rotate secrets**: Use Secrets Manager rotation for app client secrets

## Cost Considerations

Cognito pricing is based on Monthly Active Users (MAU):
- First 50,000 MAU: Free
- 50,001 - 100,000 MAU: $0.0055/MAU
- Advanced Security: Additional $0.05/MAU

For small deployments, Cognito is essentially free and eliminates Keycloak infrastructure costs.
