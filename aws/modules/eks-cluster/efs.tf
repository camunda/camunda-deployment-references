resource "aws_efs_file_system" "efs" {
  creation_token   = var.name
  performance_mode = "generalPurpose"
  encrypted        = true
}

resource "aws_efs_mount_target" "efs_mounts" {
  for_each = toset(module.vpc.private_subnets)

  file_system_id = aws_efs_file_system.efs.id
  subnet_id      = each.value

  security_groups = [aws_security_group.efs.id]
}
