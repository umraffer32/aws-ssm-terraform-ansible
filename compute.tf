resource "aws_instance" "nat" {
  tags = {
    Name = "NAT"
    Role = "ssm-nat"
  }

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.nat_sg.id]
  associate_public_ip_address = true
  source_dest_check           = false
  # key_name                    = var.key_name
  iam_instance_profile        = "SSM-EC2"
}

resource "aws_instance" "ssm_hosts" {
  count = var.ssm_host_count

  tags = {
    Name = "SSM-Host-${count.index + 1}"
    Role = "ssm-hosts"
  }

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.private_sg.id]
  iam_instance_profile   = "SSM-EC2"
}

