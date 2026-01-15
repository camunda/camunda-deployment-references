resource "aws_efs_file_system" "efs" {
  creation_token   = "${var.prefix}-efs"
  performance_mode = var.efs_performance_mode
  encrypted        = true

  throughput_mode = var.efs_throughput_mode

  provisioned_throughput_in_mibps = var.efs_throughput_mode == "provisioned" ? var.efs_provisioned_throughput_in_mibps : null
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

  tags = {
    Name = "${var.prefix}-camunda-data-access-point"
  }
}

resource "aws_efs_mount_target" "efs_mounts" {
  count = length(var.vpc_private_subnets)

  file_system_id = aws_efs_file_system.efs.id
  subnet_id      = var.vpc_private_subnets[count.index]

  security_groups = var.efs_security_group_ids
}
