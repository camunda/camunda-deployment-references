// IAM Role
resource "aws_iam_role" "roles" {
  name               = "SNSRole-${var.name}"
  assume_role_policy = <<EOF
          {
            "Version": "2012-10-17",
            "Statement": [
              {
                "Effect": "Allow",
                "Principal": {
                  "Federated": "${module.eks.oidc_provider_arn}"
                },
                "Action": "sts:AssumeRoleWithWebIdentity",
                "Condition": {
                  "StringEquals": {
                    "${module.eks.oidc_provider_id}:sub": "system:serviceaccount:camunda:sns-sa"
                  }
                }
              }
            ]
          }
EOF
}

// IAM Policy for Access
resource "aws_iam_policy" "access_policies" {
  name        = "${var.name}-access-policy"
  description = "Access policy for ${var.name}"

  policy = {
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "SNS:*"
        ],
        "Resource" : "arn:aws:sns:${var.region}:${module.eks.aws_caller_identity_account_id}:test"
      }
    ]
  }
}

// Attach the policy to the role
resource "aws_iam_role_policy_attachment" "attach_policies" {
  role       = aws_iam_role.roles.name
  policy_arn = aws_iam_policy.access_policies.arn
}
