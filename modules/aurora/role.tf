// IAM Role
resource "aws_iam_role" "roles" {
  for_each = { for idx, role in var.iam_roles_with_policies : role.role_name => role }

  name               = each.key
  assume_role_policy = each.value.trust_policy
}

// IAM Policy for Access
resource "aws_iam_policy" "access_policies" {
  for_each = { for idx, role in var.iam_roles_with_policies : role.role_name => role }

  name        = "${each.key}-access-policy"
  description = "Access policy for ${each.key}"

  policy = each.value.access_policy
}

// Attach the policy to the role
resource "aws_iam_role_policy_attachment" "attach_policies" {
  for_each = { for idx, role in var.iam_roles_with_policies : role.role_name => role }

  role       = aws_iam_role.roles[each.key].name
  policy_arn = aws_iam_policy.access_policies[each.key].arn
}
