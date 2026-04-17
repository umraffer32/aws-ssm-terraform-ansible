resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  assign_generated_ipv6_cidr_block = true
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "SSM2-vpc"
  }
}

# resource "aws_egress_only_internet_gateway" "eigw" {
#   vpc_id = aws_vpc.main.id
# }

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "SSM2-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.100.0/24"
  availability_zone       = "us-west-2a"
  # ipv6_cidr_block = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 0)
  # assign_ipv6_address_on_creation = true
  map_public_ip_on_launch = true

  tags = {
    Name = "SSM2-public-subnet-us-west-2a"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "SSM2-public-rtb"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
  # ipv6_cidr_block = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 1)
  # assign_ipv6_address_on_creation = true

  tags = {
    Name = "SSM2-private-subnet-us-west-2a"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "SSM2-private-rtb"
  }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}

# resource "aws_route" "private_ipv6" {
#   route_table_id              = aws_route_table.private.id
#   destination_ipv6_cidr_block = "::/0"
#   egress_only_gateway_id      = aws_egress_only_internet_gateway.eigw.id
# }

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

