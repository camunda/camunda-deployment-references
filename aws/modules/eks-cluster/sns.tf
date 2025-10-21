// IAM Role

locals {
  oidc_1 = replace(module.eks.oidc_provider_arn, "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/", "")
}
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
                    "${local.oidc_1}:sub": "system:serviceaccount:camunda:sns-sa"
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

  policy = <<EOF
  {
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "SNS:*"
        ],
        "Resource" : "arn:aws:sns:${var.region}:${data.aws_caller_identity.current.account_id}:test"
      }
    ]
  }
EOF

}


// Attach the policy to the role
resource "aws_iam_role_policy_attachment" "attach_policies" {
  role       = aws_iam_role.roles.name
  policy_arn = aws_iam_policy.access_policies.arn
}
