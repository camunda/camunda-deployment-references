locals {
  camunda_extra_disk_name   = "/dev/sdf"
  instance_count            = 3 # Number of EC2 instances for Camunda to run
  aws_instance_architecture = "x86_64"
  aws_instance_type = {
    x86_64 = "m7i.xlarge"
    arm64  = "m7g.xlarge"
  }
  aws_instance_type_bastion = {
    x86_64 = "t3.nano"
    arm64  = "t4g.nano"
  }
  enable_jump_host = true
  # It's recommended to pin the AMI as otherwise it will result in recreations and wipe everything.
  aws_ami = "" # If empty, the latest filtered AMI will be used
}
resource "aws_instance" "camunda" {
  count         = local.instance_count
  ami           = local.aws_ami == "" ? data.aws_ami.ami.id : local.aws_ami
  instance_type = local.aws_instance_type[local.aws_instance_architecture]
  subnet_id     = module.vpc.private_subnets[count.index]

  vpc_security_group_ids = [
    aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
    aws_security_group.allow_package_80_443.id,
    aws_security_group.allow_remote_grpc.id,
  ]

  iam_instance_profile = aws_iam_instance_profile.cloudwatch_instance_profile.name

  associate_public_ip_address = false

  key_name = aws_key_pair.main.key_name

  # Contains the OS
  root_block_device {
    volume_size = 10
    volume_type = "gp3"

    delete_on_termination = true
    encrypted             = true
    kms_key_id            = aws_kms_key.main.arn
  }

  # Automatically mounts the extra volume to keep Camunda separated from the OS
  user_data = <<-EOF
    #!/bin/bash
    # Retry mechanism to wait for the volume to be attached

    device_name="${local.camunda_extra_disk_name}"
    actual_device="/dev/nvme1n1"
    mount_point="/opt/camunda"
    admin_user="ubuntu"
    retries=10

    # Wait for the device to be attached
    while [ $retries -gt 0 ]; do
      if lsblk $actual_device 2>/dev/null || lsblk $device_name 2>/dev/null; then
        # Use the actual device that exists
        if lsblk $actual_device 2>/dev/null; then
          device_name=$actual_device
        fi
        echo "Device $device_name found"
        break
      else
        echo "Waiting for device to be attached..."
        sleep 10
        retries=$((retries - 1))
      fi
    done

    if [ $retries -eq 0 ]; then
      echo "Error: Device not found after waiting"
      exit 1
    fi

    # Check if the device is already mounted
    if ! mount | grep $mount_point > /dev/null; then
      # Check if the filesystem exists
      if ! file -s -L $device_name | grep ext4 > /dev/null; then
        mkfs -t ext4 $device_name
      fi
      mkdir -p $mount_point
      mount $device_name $mount_point

      # Add the device to /etc/fstab to persist the mount on restart
      output=$(lsblk $device_name -o +UUID)
      uuid=$(echo "$output" | tail -n 1 | awk '{print $NF}')
      echo "UUID=$uuid $mount_point ext4 defaults,nofail 0 2" >> /etc/fstab
      systemctl daemon-reload
    fi
    chown $admin_user:$admin_user $mount_point
  EOF

  tags = {
    Name = "${var.prefix}-instance-${count.index}"
  }
}

# Contains the Camunda data to have a separate lifecycle
resource "aws_ebs_volume" "camunda" {
  count = local.instance_count

  availability_zone = module.vpc.azs[count.index]
  size              = 50
  type              = "gp3"
  encrypted         = true
  kms_key_id        = aws_kms_key.main.arn

  tags = {
    Name = "${var.prefix}-extra-volume-${count.index}"
  }
}

# Attach EBS Volume to EC2 Instance
resource "aws_volume_attachment" "ebs_attachment" {
  count = local.instance_count

  device_name = local.camunda_extra_disk_name
  volume_id   = aws_ebs_volume.camunda[count.index].id
  instance_id = aws_instance.camunda[count.index].id
}

# Bastion host to access the instances within the private network without exposing those directly
resource "aws_instance" "bastion" {
  count = local.enable_jump_host ? 1 : 0

  ami           = local.aws_ami == "" ? data.aws_ami.ami.id : local.aws_ami
  instance_type = local.aws_instance_type_bastion[local.aws_instance_architecture]
  subnet_id     = module.vpc.public_subnets[0]

  vpc_security_group_ids = [
    aws_security_group.allow_ssh.id,
    aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
  ]

  associate_public_ip_address = true

  key_name = aws_key_pair.main.key_name

  tags = {
    Name = "${var.prefix}-bastion"
  }
}

# Outputs
output "bastion_ip" {
  value       = join("", aws_instance.bastion[*].public_ip)
  description = "(Optional) The public IP address of the Bastion instance."
}

output "camunda_ips" {
  value       = [for instance in aws_instance.camunda : instance.private_ip]
  description = "The private IP addresses of the Camunda instances."
}
