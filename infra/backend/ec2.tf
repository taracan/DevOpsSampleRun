# ec2.tf: a tiny admin server for database access (EC2).
#
# Why: RDS is private, so you can't connect to it from your laptop. This
# small Linux server sits in a private subnet next to RDS and has the
# PostgreSQL client (psql) installed, so you can run SQL by hand.
#
# How you get in: AWS Systems Manager Session Manager. No SSH keys, no
# open ports, no public IP. The SSM agent on the instance connects OUT
# to AWS (through the NAT gateway), and you open a shell from:
#   AWS console -> EC2 -> Instances -> smallproject-admin -> Connect
#     -> Session Manager -> Connect
# Then:
#   psql -h <db_endpoint output> -U postgres -d smallproject
#   (the password: Secrets Manager -> rds!db-... -> Retrieve secret value)
#   SELECT * FROM users;
#
# The instance role only allows SSM (iam.tf). It can't read the DB
# password itself; you paste it in.
#
# Cost: t4g.micro is free-tier eligible (750 hours/month); about $6/month after.

# Latest Amazon Linux 2023 image for ARM (Graviton), published by AWS.
data "aws_ssm_parameter" "al2023_arm" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_instance" "admin" {
  ami                    = data.aws_ssm_parameter.al2023_arm.value
  instance_type          = "t4g.micro" # free-tier eligible (the Free plan allows only these)
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  # Runs once at first boot: install the PostgreSQL client.
  user_data = <<-EOF
    #!/bin/bash
    dnf install -y postgresql16
  EOF

  # IMDSv2: instance metadata requires a session token (blocks a common
  # credential-theft trick).
  metadata_options {
    http_tokens = "required"
  }

  tags = { Name = "${local.name}-admin" }

  # Don't replace the server every time AWS publishes a newer image.
  lifecycle {
    ignore_changes = [ami]
  }
}
