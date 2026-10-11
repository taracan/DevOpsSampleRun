# Each layer only trusts the layer in front of it:
#   CloudFront -> ALB -> ECS -> RDS <- EC2 admin
# Note: aws_security_group without egress rules has NO egress (Terraform
# removes AWS's default allow-all rule), so egress is added explicitly.

# AWS-maintained list of CloudFront origin-facing IP ranges.
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# ---------- ALB: CloudFront only ----------
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "ALB: HTTP from CloudFront only"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name}-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_cloudfront" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from CloudFront"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ecs" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to ECS tasks"
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.ecs.id
}

# ---------- ECS: ALB only ----------
resource "aws_security_group" "ecs" {
  name        = "${var.name}-ecs"
  description = "ECS tasks: app port from ALB only"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name}-ecs" }
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "App port from ALB"
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.alb.id
}

# Outbound: RDS, plus HTTPS to ECR, CloudWatch, Secrets Manager via NAT.
resource "aws_vpc_security_group_egress_rule" "ecs_all" {
  security_group_id = aws_security_group.ecs.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------- EC2 admin host: no inbound (SSM only) ----------
resource "aws_security_group" "ec2_admin" {
  name        = "${var.name}-ec2-admin"
  description = "Admin host: no inbound, reached through SSM"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name}-ec2-admin" }
}

# Outbound: RDS, plus HTTPS to SSM and package repos via NAT.
resource "aws_vpc_security_group_egress_rule" "ec2_admin_all" {
  security_group_id = aws_security_group.ec2_admin.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------- RDS: ECS and EC2 admin only ----------
resource "aws_security_group" "rds" {
  name        = "${var.name}-rds"
  description = "RDS: PostgreSQL from ECS and admin host only"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name}-rds" }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_ecs" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL from ECS"
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = aws_security_group.ecs.id
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_ec2_admin" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL from admin host"
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = aws_security_group.ec2_admin.id
}
