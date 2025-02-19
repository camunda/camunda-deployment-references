# Migration Guide from v2 to v3

## Key Changes

### Aurora and OpenSearch IAM Role Management

In version **v2**, the **Aurora** and **OpenSearch** modules only supported creating **one IAM role** with a single **access policy** and a single **trust policy**.

Starting from version **v3**, these modules now accept an array, allowing the creation of multiple IAM roles. This change enables more granular access control, for example, granting access to specific databases only to certain ServiceAccounts, improving security and flexibility.

### Removed Input Variables

The following input variables have been **removed** in v3:

#### OpenSearch
- `iam_create_opensearch_role`
- `iam_opensearch_role_name`
- `iam_role_trust_policy`
- `iam_opensearch_access_policy`

#### Aurora
- `iam_create_aurora_role`
- `iam_aurora_role_name`
- `iam_role_trust_policy`
- `iam_aurora_access_policy`

### New Input Variables

These variables have been **replaced** by a new array input:

```hcl
variable "iam_roles_with_policies" {
  description = "List of roles with their trust and access policies"
  type = list(object({
    # Name of the Role to create
    role_name = string

    # Assume role trust policy for this role as a JSON string
    trust_policy = string

    # Access policy allowing specific actions as a JSON string
    access_policy = string
  }))

  # By default, don't create any role and associated policies.
  default = []
}
```

For **v3**, there is a separate `iam_roles_with_policies` variable for both **Aurora** and **OpenSearch**, allowing you to specify multiple roles with distinct access and trust policies for each service.

### Migration Example

To migrate from **v2** to **v3**, you need to refactor your configuration by consolidating the removed variables into the new `iam_roles_with_policies` array.

Here’s an example of how you can migrate the variables:

#### v2 Aurora Configuration

```hcl
# Version 2 inputs for Aurora
iam_create_aurora_role        = true
iam_aurora_role_name          = "AuroraRole"
iam_role_trust_policy         = jsonencode({
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "rds.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
})
iam_aurora_access_policy      = jsonencode({
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [ "rds-db:connect" ],
    "Resource": "arn:aws:rds-db:us-west-2:123456789012:dbuser:*/my-db-user"
  }]
})
```

#### v3 Aurora Configuration

```hcl
# Version 3 input using iam_roles_with_policies
variable "iam_roles_with_policies" {
  description = "List of roles with their trust and access policies"
  type = list(object({
    role_name = string
    trust_policy = string
    access_policy = string
  }))
  default = []
}

# Migrated Aurora roles
iam_roles_with_policies = [
  {
    role_name = "AuroraRole"
    trust_policy = <<EOF
      {
        "Version": "2012-10-17",
        "Statement": [{
          "Effect": "Allow",
          "Principal": { "Service": "rds.amazonaws.com" },
          "Action": "sts:AssumeRole"
        }]
      }
    EOF
    access_policy = <<EOF
      {
        "Version": "2012-10-17",
        "Statement": [{
          "Effect": "Allow",
          "Action": [ "rds-db:connect" ],
          "Resource": "arn:aws:rds-db:us-west-2:123456789012:dbuser:*/my-db-user"
        }]
      }
    EOF
  }
]
```

#### v2 OpenSearch Configuration

```hcl
# Version 2 inputs for OpenSearch
iam_create_opensearch_role    = true
iam_opensearch_role_name      = "OpenSearchRole"
iam_role_trust_policy         = jsonencode({
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "es.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
})
iam_opensearch_access_policy  = jsonencode({
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [ "es:ESHttpGet", "es:ESHttpPut" ],
    "Resource": "arn:aws:es:us-west-2:123456789012:domain/my-opensearch-domain/*"
  }]
})
```

#### v3 OpenSearch Configuration

```hcl
# Version 3 input using iam_roles_with_policies for OpenSearch
iam_roles_with_policies = [
  {
    role_name = "OpenSearchRole"
    trust_policy = <<EOF
      {
        "Version": "2012-10-17",
        "Statement": [{
          "Effect": "Allow",
          "Principal": { "Service": "es.amazonaws.com" },
          "Action": "sts:AssumeRole"
        }]
      }
    EOF
    access_policy = <<EOF
      {
        "Version": "2012-10-17",
        "Statement": [{
          "Effect": "Allow",
          "Action": [ "es:ESHttpGet", "es:ESHttpPut" ],
          "Resource": "arn:aws:es:us-west-2:123456789012:domain/my-opensearch-domain/*"
        }]
      }
    EOF
  }
]
```

### Conclusion

Migrating from **v2** to **v3** involves transitioning from individual role management (one role per service) to a more scalable and flexible array-based configuration. This change provides finer control over multiple roles and policies, especially useful for granting specific service accounts access to specific resources.

Simply move the existing values from the removed variables to the new `iam_roles_with_policies` input format.
