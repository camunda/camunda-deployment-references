resource "aws_efs_file_system" "efs" {
  creation_token   = "${var.prefix}-efs"
  performance_mode = "generalPurpose"
  encrypted        = true

  throughput_mode = "provisioned"
  provisioned_throughput_in_mibps = 125 # gp3 baseline
}

resource "aws_efs_access_point" "camunda_data" {
  file_system_id = aws_efs_file_system.efs.id
  
  root_directory {
    path = "/usr/local/camunda/data"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }
  
  posix_user {
    gid = 1000
    uid = 1000
  }
  
  depends_on = [aws_efs_file_system.efs]
  
  tags = {
    Name = "${var.prefix}-camunda-data-access-point"
  }
}

# EFS mount targets are required for ECS tasks to access the file system
# Requires currently a two step apply
# First vpc via `terraform apply -target=module.vpc`
resource "aws_efs_mount_target" "efs_mounts" {
  for_each = toset(module.vpc.private_subnets)

  file_system_id = aws_efs_file_system.efs.id
  subnet_id      = each.value

  security_groups = [aws_security_group.efs.id]
  
  depends_on = [
    aws_efs_file_system.efs,
    aws_security_group.efs,
    module.vpc
  ]
}
