output "backup_bucket_name" {
  value       = module.backup.bucket_name
  description = "Name of the backup bucket"
}

output "backup_access_policy_arn" {
  value       = module.backup.access_policy_arn
  description = "IAM policy granting access to the backup bucket; attach it to the Orchestration Cluster task role"
}

output "lease_buckets" {
  value = {
    for zone, m in module.lease : zone => {
      bucket_name       = m.bucket_name
      access_policy_arn = m.access_policy_arn
    }
  }
  description = "Per zone: the node ID lease bucket and the IAM policy that grants access to it"
}
