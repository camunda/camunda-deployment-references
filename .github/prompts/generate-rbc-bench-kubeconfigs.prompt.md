---
description: "Generate SA-based kubeconfigs for the RBC benchmark dual-region EKS clusters (rbc-bench-7ce10). Use when clusters have been recreated and you need kubeconfigs that work without AWS credentials."
agent: "agent"
---

# Generate SA-based kubeconfigs for RBC benchmark clusters

## Context

The RBC benchmark uses two persistent EKS clusters in a dual-region setup:
- **us-east-1**: `rbc-bench-7ce10-us-east-1`
- **us-east-2**: `rbc-bench-7ce10-us-east-2`

AWS account: `444804106854`, AWS profile: `infex`.

When clusters are recreated (via CI or manually), the old kubeconfigs become invalid. This prompt regenerates SA-based kubeconfigs that work **without any AWS credentials**.

## Procedure

Execute these steps in order. Use `bash -c '...'` wrappers since the user's shell is **fish**.

### 1. Ensure AWS SSO session is active

```bash
aws sts get-caller-identity --profile infex
```

If it fails with a token error, run:

```bash
aws sso login --profile infex
```

### 2. Generate temporary AWS-based kubeconfigs

```bash
aws eks update-kubeconfig --region us-east-1 --name rbc-bench-7ce10-us-east-1 --profile infex --kubeconfig /tmp/kubeconfig-rbc-bench-us-east-1.yml
aws eks update-kubeconfig --region us-east-2 --name rbc-bench-7ce10-us-east-2 --profile infex --kubeconfig /tmp/kubeconfig-rbc-bench-us-east-2.yml
```

### 3. Add SSO role as cluster admin (needed after cluster recreation)

The SSO role ARN is:
```
arn:aws:iam::444804106854:role/aws-reserved/sso.amazonaws.com/eu-central-1/AWSReservedSSO_SystemAdministrator_555f3db864dcee7e
```

For **each cluster**, create an access entry and associate the admin policy:

```bash
aws eks create-access-entry \
  --cluster-name <CLUSTER_NAME> \
  --region <REGION> \
  --profile infex \
  --principal-arn "arn:aws:iam::444804106854:role/aws-reserved/sso.amazonaws.com/eu-central-1/AWSReservedSSO_SystemAdministrator_555f3db864dcee7e"

aws eks associate-access-policy \
  --cluster-name <CLUSTER_NAME> \
  --region <REGION> \
  --profile infex \
  --principal-arn "arn:aws:iam::444804106854:role/aws-reserved/sso.amazonaws.com/eu-central-1/AWSReservedSSO_SystemAdministrator_555f3db864dcee7e" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

If the access entry already exists, the command will error — that's fine, continue.

### 4. Verify cluster access works

```bash
KUBECONFIG=/tmp/kubeconfig-rbc-bench-us-east-1.yml kubectl get nodes
KUBECONFIG=/tmp/kubeconfig-rbc-bench-us-east-2.yml kubectl get nodes
```

Both should return 6 Ready nodes.

### 5. Create the SA-based kubeconfigs

Write this script to `/tmp/gen-sa-kubeconfig.sh` and run it with `bash /tmp/gen-sa-kubeconfig.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

CLUSTER1_NAME="rbc-bench-7ce10-us-east-1"
CLUSTER2_NAME="rbc-bench-7ce10-us-east-2"
KC1="/tmp/kubeconfig-rbc-bench-us-east-1.yml"
KC2="/tmp/kubeconfig-rbc-bench-us-east-2.yml"
OUT1="/tmp/kubeconfig-sa-rbc-bench-us-east-1.yml"
OUT2="/tmp/kubeconfig-sa-rbc-bench-us-east-2.yml"

SA_SECRET='{"apiVersion":"v1","kind":"Secret","metadata":{"name":"admin-sa-token","namespace":"kube-system","annotations":{"kubernetes.io/service-account.name":"admin-sa"}},"type":"kubernetes.io/service-account-token"}'

generate_sa_kubeconfig() {
  local kc="$1" out="$2" cluster_name="$3"

  echo "=== Processing $cluster_name ==="

  KUBECONFIG="$kc" kubectl -n kube-system get sa admin-sa >/dev/null 2>&1 || \
    KUBECONFIG="$kc" kubectl -n kube-system create serviceaccount admin-sa

  KUBECONFIG="$kc" kubectl get clusterrolebinding admin-sa-binding >/dev/null 2>&1 || \
    KUBECONFIG="$kc" kubectl create clusterrolebinding admin-sa-binding \
      --clusterrole=cluster-admin --serviceaccount=kube-system:admin-sa

  KUBECONFIG="$kc" kubectl -n kube-system get secret admin-sa-token >/dev/null 2>&1 || \
    echo "$SA_SECRET" | KUBECONFIG="$kc" kubectl -n kube-system apply -f -

  echo "Waiting for token..."
  TOKEN=""
  for i in $(seq 1 10); do
    TOKEN=$(KUBECONFIG="$kc" kubectl -n kube-system get secret admin-sa-token -o jsonpath='{.data.token}' 2>/dev/null || true)
    if [ -n "$TOKEN" ]; then break; fi
    sleep 1
  done

  if [ -z "$TOKEN" ]; then
    echo "ERROR: Token not found for $cluster_name"; return 1
  fi

  DECODED_TOKEN=$(echo "$TOKEN" | base64 -d)
  CA_DATA=$(KUBECONFIG="$kc" kubectl -n kube-system get secret admin-sa-token -o jsonpath='{.data.ca\.crt}')
  SERVER=$(KUBECONFIG="$kc" kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

  echo "Server: $SERVER"

  cat > "$out" <<KUBECONFIG
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${CA_DATA}
    server: ${SERVER}
  name: ${cluster_name}
contexts:
- context:
    cluster: ${cluster_name}
    user: admin-sa
  name: ${cluster_name}
current-context: ${cluster_name}
users:
- name: admin-sa
  user:
    token: ${DECODED_TOKEN}
KUBECONFIG

  echo "Kubeconfig written to $out"
  echo "Verifying..."
  KUBECONFIG="$out" kubectl get nodes
  echo ""
}

generate_sa_kubeconfig "$KC1" "$OUT1" "$CLUSTER1_NAME"
generate_sa_kubeconfig "$KC2" "$OUT2" "$CLUSTER2_NAME"

echo "=== DONE ==="
echo "  $OUT1"
echo "  $OUT2"
```

### 6. Final output

The SA-based kubeconfigs are at:
- `/tmp/kubeconfig-sa-rbc-bench-us-east-1.yml`
- `/tmp/kubeconfig-sa-rbc-bench-us-east-2.yml`

Usage in fish:
```fish
set -x KUBECONFIG /tmp/kubeconfig-sa-rbc-bench-us-east-1.yml
kubectl get pods -n c8-snap-cluster-0
```

## Important notes

- The user's shell may be **fish** or **bash**. Detect it first (`echo $SHELL` or check the terminal). If fish, wrap commands in `bash -c '...'` or write scripts to `/tmp/` and run with `bash`. If bash, run commands directly.
- The AWS profile is `infex` (not `infraex` which is CI).
- If `aws eks create-access-entry` says the entry already exists, skip to the next step.
- The script is idempotent: it checks if SA/binding/secret exist before creating them.
