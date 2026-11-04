prefix     = "camunda-demo"
aws_region = "eu-west-1"
zones      = ["zone-a"]

# Dev and test only: lets terraform destroy remove buckets that contain objects.
force_destroy = true
