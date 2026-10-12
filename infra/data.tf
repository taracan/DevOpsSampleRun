# data.tf: where data lives. An RDS PostgreSQL database and two S3 buckets.
#
# RDS (managed PostgreSQL):
#   - Stores the users table. The backend creates the table on its first
#     start (app/db/init_db.py), so no migration step is needed.
#   - Placed in the PRIVATE subnets and not publicly accessible. Only
#     ECS and the EC2 admin host can connect (rds security group,
#     network.tf).
#   - The master password is created and stored by RDS itself in
#     Secrets Manager (manage_master_user_password). It never appears
#     in code, Terraform files or GitHub. ECS reads it from there at
#     start-up (step 7).
#   - Storage is encrypted, with daily automated backups kept 1 day.
#
# S3 buckets (private by default: AWS blocks public access and encrypts
# every new bucket automatically):
#   - web:     the React build. Only CloudFront reads it (step 8);
#              GitHub Actions uploads it (step 10).
#   - reports: nightly CSV reports from the job (step 9). A lifecycle
#              rule moves them to cheaper Glacier storage after 30 days.
#
# Dev-friendly settings: skip_final_snapshot and force_destroy let
# `terraform destroy` remove everything, including data. Production
# would keep a final snapshot and protect the buckets.
#
# Cost: db.t4g.micro is about $13/month (free tier eligible); the
# buckets cost cents.

# ---------- RDS ----------
# Which subnets RDS may use: the two private ones (one per AZ).
resource "aws_db_subnet_group" "main" {
  name       = local.name
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "main" {
  identifier     = local.name
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro"

  allocated_storage = 20 # GB
  storage_type      = "gp3"
  storage_encrypted = true

  db_name                     = "smallproject" # matches DB_NAME in app/core/config.py
  username                    = "postgres"
  manage_master_user_password = true # RDS generates the password into Secrets Manager

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  backup_retention_period = 1
  apply_immediately       = true
  skip_final_snapshot     = true # dev only: no snapshot on destroy
}

# ---------- S3 ----------
resource "aws_s3_bucket" "web" {
  bucket        = local.web_bucket
  force_destroy = true # dev only: destroy even if not empty
}

resource "aws_s3_bucket" "reports" {
  bucket        = local.reports_bucket
  force_destroy = true # dev only: destroy even if not empty
}

# Old reports move to Glacier (about 80% cheaper storage) after 30 days.
resource "aws_s3_bucket_lifecycle_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    id     = "reports-to-glacier"
    status = "Enabled"

    filter {
      prefix = "reports/"
    }

    transition {
      days          = 30
      storage_class = "GLACIER"
    }
  }
}
