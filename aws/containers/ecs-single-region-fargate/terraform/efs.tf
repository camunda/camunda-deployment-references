resource "aws_efs_file_system" "efs" {
  count = var.camunda_count

  creation_token   = "${var.prefix}-efs-${count.index}"
  performance_mode = "generalPurpose"
  encrypted        = true

  throughput_mode = "provisioned"
  provisioned_throughput_in_mibps = 125 # gp3 baseline
}

resource "aws_efs_access_point" "camunda_data" {
  count = var.camunda_count

  file_system_id = aws_efs_file_system.efs[count.index].id
  
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
    Name = "${var.prefix}-camunda-data-access-point-${count.index}"
  }
}

# EFS mount targets are required for ECS tasks to access the file system
# Requires currently a two step apply
# First vpc via `terraform apply -target=module.vpc`
resource "aws_efs_mount_target" "efs_mounts_zone_0" {
  count = var.camunda_count

  file_system_id = aws_efs_file_system.efs[count.index].id
  subnet_id      = module.vpc.private_subnets[0]

  security_groups = [aws_security_group.efs.id]
  
  depends_on = [
    aws_security_group.efs,
    module.vpc
  ]
}

resource "aws_efs_mount_target" "efs_mounts_zone_1" {
  count = var.camunda_count

  file_system_id = aws_efs_file_system.efs[count.index].id
  subnet_id      = module.vpc.private_subnets[1]

  security_groups = [aws_security_group.efs.id]
  
  depends_on = [
    aws_security_group.efs,
    module.vpc
  ]
}

resource "aws_efs_mount_target" "efs_mounts_zone_2" {
  count = var.camunda_count

  file_system_id = aws_efs_file_system.efs[count.index].id
  subnet_id      = module.vpc.private_subnets[2]

  security_groups = [aws_security_group.efs.id]
  
  depends_on = [
    aws_security_group.efs,
    module.vpc
  ]
}
