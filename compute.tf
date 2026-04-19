resource "aws_instance" "nat" {
  tags = {
    Name = "NAT"
    Role = "ssm-nat"
  }

  metadata_options {
  http_tokens = "required"
  }

  ami                         = data.aws_ami.debian.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.nat_sg.id]
  associate_public_ip_address = true
  # ipv6_address_count          = 1
  source_dest_check           = false
  # key_name                    = var.key_name
  iam_instance_profile        = "SSM-EC2"
  
  user_data = <<-EOF
  #!/bin/bash
  set -eux

  export DEBIAN_FRONTEND=noninteractive

  sleep 10
  IFACE=$(ip route | awk '/default/ {print $5; exit}')

  apt update

  mkdir -p /tmp/ssm
  cd /tmp/ssm
  wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
  dpkg -i amazon-ssm-agent.deb || apt -f install -y
  systemctl enable amazon-ssm-agent
  systemctl start amazon-ssm-agent

  apt install -y iptables-persistent
  echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-nat.conf
  sysctl --system

  iptables -t nat -A POSTROUTING -o $IFACE -j MASQUERADE
  iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
  iptables -A FORWARD -j ACCEPT

  netfilter-persistent save
  systemctl enable netfilter-persistent
  EOF
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
  # ipv6_address_count = 1
  # user_data = <<-EOF
  # #!/bin/bash
  # set -eux

  # nohup bash -c '
  # for i in {1..60}; do
  #   if curl -fsS --max-time 2 https://ssm.us-west-2.amazonaws.com >/dev/null; then
  #     systemctl enable amazon-ssm-agent || true
  #     systemctl restart amazon-ssm-agent || true
  #     exit 0
  #   fi
  #   sleep 5
  # done
  # ' >/var/log/ssm-recover.log 2>&1 &
  # EOF
}

