# network.tf: the private network everything runs in (VPC, subnets,
# internet access, firewalls).
#
#   Internet
#      |
#   Internet gateway
#      |
#   PUBLIC subnets (2 AZs) ...... load balancer, NAT gateway
#      |  (NAT: outbound only)
#   PRIVATE subnets (2 AZs) ..... ECS tasks, RDS database, EC2 admin host
#
# Public subnets have a route to the internet gateway, so things there
# can be reached from the internet (only the load balancer lives there).
# Private subnets can't be reached from the internet. They go OUT
# through the NAT gateway (e.g. ECS pulling images from ECR), but nothing
# can come IN.
#
# Security groups are firewalls on each resource. Each layer only
# accepts traffic from the layer in front of it:
#   CloudFront -> ALB (port 80) -> ECS (port 8000) -> RDS (port 5432) <- EC2
#
# Cost: the NAT gateway is about $32/month plus data; the rest is free.

# ---------- VPC ----------
resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true # needed for RDS and service endpoints
  enable_dns_hostnames = true

  tags = { Name = "${local.name}-vpc" }
}

# ---------- Subnets: one public and one private per AZ ----------
resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = local.public_subnet_cidrs[count.index]

  tags = { Name = "${local.name}-public-${local.azs[count.index]}" }
}

resource "aws_subnet" "private" {
  count = length(local.azs)

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = local.private_subnet_cidrs[count.index]

  tags = { Name = "${local.name}-private-${local.azs[count.index]}" }
}

# ---------- Internet access ----------
# Internet gateway: the VPC's door to the internet (public subnets).
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name}-igw" }
}

# NAT gateway: lets private subnets reach out (outbound only). One is
# enough here; production would use one per AZ.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "${local.name}-nat" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = { Name = "${local.name}-nat" }

  depends_on = [aws_internet_gateway.main]
}

# ---------- Route tables: where traffic goes ----------
# Public: everything not inside the VPC -> internet gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.name}-public" }
}

# Private: everything not inside the VPC -> NAT gateway.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = { Name = "${local.name}-private" }
}

resource "aws_route_table_association" "public" {
  count = length(local.azs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = length(local.azs)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ---------- Security groups (firewalls) ----------
# Inbound (ingress) is locked down per layer. Outbound (egress) is open,
# so services can reach AWS APIs and each other.

# AWS-maintained list of CloudFront's IP ranges.
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# Load balancer: HTTP only from CloudFront, so nobody can skip CloudFront.
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "ALB: HTTP from CloudFront only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from CloudFront"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS tasks: the app port only from the load balancer.
resource "aws_security_group" "ecs" {
  name        = "${local.name}-ecs"
  description = "ECS tasks: app port from the ALB only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App port from the ALB"
    from_port       = local.app_port
    to_port         = local.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 admin host: no inbound at all. You connect through SSM Session
# Manager, which works over outbound connections only (no SSH).
resource "aws_security_group" "ec2" {
  name        = "${local.name}-ec2"
  description = "EC2 admin host: no inbound (SSM only)"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# RDS database: PostgreSQL only from the ECS tasks and the EC2 admin host.
resource "aws_security_group" "rds" {
  name        = "${local.name}-rds"
  description = "RDS: PostgreSQL from ECS and the EC2 admin host only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from ECS and EC2"
    from_port       = local.db_port
    to_port         = local.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id, aws_security_group.ec2.id]
  }
}
