resource "aws_security_group" "nat_sg" {
  name        = "SSM2-nat-sg"
  description = "Security group for NAT instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow all traffic from private subnet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    security_groups = [aws_security_group.private_sg.id] 
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    # ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "SSM2-nat-sg"
  }
}

resource "aws_security_group" "private_sg" {
  name        = "SSM2-private-sg"
  description = "Security group for SSM hosts"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [ "0.0.0.0/0" ]
    # ipv6_cidr_blocks = ["::/0"]
  }



  tags = {
    Name = "SSM2-private-sg"
  }
}

