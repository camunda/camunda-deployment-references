resource "aws_instance" "camunda" {
  count         = var.instance_count
  ami           = var.aws_ami == "" ? data.aws_ami.debian.id : var.aws_ami
  instance_type = var.aws_instance_type
  subnet_id     = module.vpc.private_subnets[count.index]

  vpc_security_group_ids = [
    aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
    aws_security_group.allow_remote_80_443.id
  ]

  associate_public_ip_address = false

  key_name = aws_key_pair.main.key_name

  root_block_device {
    volume_size = 50
    volume_type = "gp3"

    delete_on_termination = var.delete_on_termination
    encrypted             = true
    kms_key_id            = aws_kms_key.main.arn
  }

  tags = {
    Name = "camunda-instance-${count.index}"
  }
}

resource "aws_instance" "bastion" {
  count = var.enable_jump_host ? 1 : 0

  ami           = var.aws_ami == "" ? data.aws_ami.debian.id : var.aws_ami
  instance_type = var.aws_instance_type_bastion
  subnet_id     = module.vpc.public_subnets[0]

  vpc_security_group_ids = [
    aws_security_group.allow_ssh.id,
  ]

  associate_public_ip_address = true

  key_name = aws_key_pair.main.key_name

  tags = {
    Name = "camunda-bastion"
  }
}
