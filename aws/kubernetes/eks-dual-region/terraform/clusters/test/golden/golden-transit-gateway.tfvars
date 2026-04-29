# use this file for vars without default values
# for the golden file generation with transit gateway connectivity

aws_profile        = null # uses default AWS credential chain (env vars, default profile, instance profile)
cluster_name       = "camunda"
connectivity_type  = "transit-gateway"
transit_gateway_id = "tgw-0123456789abcdef0"
