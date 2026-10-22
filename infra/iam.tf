# iam.tf: who is allowed to do what in AWS (IAM roles).
#
# What a role is: a set of permissions that an AWS service (or GitHub
# Actions) "assumes" to get short-lived credentials. No passwords and no
# long-lived access keys are involved anywhere. Each role has two parts:
#   - trust policy (assume_role_policy): WHO may use the role
#   - permissions (policies): WHAT the role may do
#
# Roles in this project, each with only the permissions it needs:
#   ecs_execution  ECS itself, starting a container: pull the image
#                  from ECR, write logs, read the DB password from
#                  Secrets Manager
#   ecs_task       the code inside the container: write reports to S3
#   github         GitHub Actions deploy workflow (step 10), main
#                  branch only: push image, run the database migrations
#                  as a one-off ECS task (Phase B step 8), redeploy ECS,
#                  upload the website, clear the CloudFront cache;
#                  snapshot the database and run the restore drill
#                  (Phase B step 9)
#   ec2            the EC2 admin host (step 9): SSM Session Manager only
#   sfn            Step Functions (step 9): run the nightly report task;
#                  Phase B step 7: restart the backend service
#   scheduler      EventBridge Scheduler (step 9): start Step Functions
#   events         EventBridge rules (Phase B step 7): start the restart
#                  workflow when the DB password has been rotated
#
# Secrets Manager: the DB password secret is created and rotated by RDS
# itself (manage_master_user_password, data.tf), so it never appears in
# code. The execution role may read exactly that one secret.

# Reused trust policy: "ECS tasks in this account may use this role".
data "aws_iam_policy_document" "ecs_tasks_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }
  }
}

# ---------- ECS task execution role ----------
resource "aws_iam_role" "ecs_execution" {
  name               = "${local.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

# AWS-managed policy: pull images from ECR and write CloudWatch logs.
resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Read the DB password so ECS can pass it to the container as DB_PASSWORD.
resource "aws_iam_role_policy" "ecs_execution_secret" {
  name = "read-db-secret"
  role = aws_iam_role.ecs_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = aws_db_instance.main.master_user_secret[0].secret_arn
    }]
  })
}

# ---------- ECS task role (the app's own permissions) ----------
# Used by both the API and the nightly report (same image). The API
# needs no AWS access; the report writes CSVs under reports/.
resource "aws_iam_role" "ecs_task" {
  name               = "${local.name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

resource "aws_iam_role_policy" "ecs_task" {
  name = "write-reports"
  role = aws_iam_role.ecs_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:PutObject"
      Resource = "arn:aws:s3:::${local.reports_bucket}/reports/*"
    }]
  })
}

# ---------- GitHub Actions (OIDC) ----------
# OIDC: GitHub gives each workflow run a signed token, and AWS trusts
# tokens from GitHub's issuer. So no AWS keys are stored in GitHub.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "github" {
  name = "${local.name}-github-actions"

  # Only workflows running on the main branch of this repo. GitHub puts
  # immutable IDs in the token subject (owner@<owner id>/repo@<repo id>),
  # so a renamed or re-created repo with the same name can't match.
  # See: gh api repos/taracan/DevOpsSampleRun/actions/oidc/customization/sub
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:taracan@47918634/DevOpsSampleRun@1410627250:ref:refs/heads/main"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github" {
  name = "deploy"
  role = aws_iam_role.github.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrLogin" # this action can't be limited to one repo
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "EcrPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage", # docker push reads existing manifests
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
        ]
        Resource = "arn:aws:ecr:${local.region}:${local.account}:repository/${local.ecr_repo}"
      },
      {
        Sid      = "EcsRedeploy" # restart the service on the new image
        Effect   = "Allow"
        Action   = ["ecs:UpdateService", "ecs:DescribeServices"]
        Resource = "arn:aws:ecs:${local.region}:${local.account}:service/${local.cluster}/${local.service}"
      },
      {
        Sid      = "WebsiteList"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::${local.web_bucket}"
      },
      {
        Sid      = "WebsiteUpload" # aws s3 sync --delete
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::${local.web_bucket}/*"
      },
      {
        Sid      = "CacheClear" # only this site's distribution (cdn.tf)
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"] # Get: wait until done
        Resource = aws_cloudfront_distribution.main.arn
      },
      # Phase B step 8: run the database migrations as a one-off ECS task
      # (deploy.yml), wait for it, and print its log.
      {
        Sid      = "MigrationRunTask" # only the backend task definition
        Effect   = "Allow"
        Action   = "ecs:RunTask"
        Resource = "arn:aws:ecs:${local.region}:${local.account}:task-definition/${local.task_family}:*"
      },
      {
        Sid      = "MigrationWatchTask" # wait for it to stop, read its exit code
        Effect   = "Allow"
        Action   = "ecs:DescribeTasks"
        Resource = "arn:aws:ecs:${local.region}:${local.account}:task/${local.cluster}/*"
      },
      {
        Sid      = "MigrationPassRoles" # hand the two ECS roles to the task, for ECS only
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = [aws_iam_role.ecs_execution.arn, aws_iam_role.ecs_task.arn]
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      },
      {
        Sid    = "MigrationLogs" # read the task's log lines
        Effect = "Allow"
        Action = "logs:GetLogEvents"
        # "<log group ARN>:*" is the form IAM matches for GetLogEvents
        # (checked with aws iam simulate-custom-policy; ":log-stream:*" was denied).
        Resource = "${aws_cloudwatch_log_group.backend.arn}:*"
      },
      # Phase B step 9: database snapshots before migrations (deploy.yml)
      # and the monthly restore drill (restore-drill.yml). Production can be
      # snapshotted and read, never deleted or overwritten: delete/restore
      # only work on the drill copy and on smallproject-* snapshots.
      {
        Sid    = "RdsSnapshotCreate" # snapshot production
        Effect = "Allow"
        Action = "rds:CreateDBSnapshot"
        Resource = [
          "arn:aws:rds:${local.region}:${local.account}:db:${local.name}",
          "arn:aws:rds:${local.region}:${local.account}:snapshot:${local.name}-*",
        ]
      },
      {
        Sid    = "RdsDescribe" # wait for snapshots and the drill copy, read settings
        Effect = "Allow"
        Action = ["rds:DescribeDBSnapshots", "rds:DescribeDBInstances"]
        Resource = [
          "arn:aws:rds:${local.region}:${local.account}:db:${local.name}*",
          "arn:aws:rds:${local.region}:${local.account}:snapshot:${local.name}-*",
        ]
      },
      {
        Sid    = "RdsSnapshotDelete" # keep 3 pre-deploy snapshots; remove drill snapshots
        Effect = "Allow"
        Action = "rds:DeleteDBSnapshot"
        Resource = [
          "arn:aws:rds:${local.region}:${local.account}:snapshot:${local.name}-predeploy-*",
          "arn:aws:rds:${local.region}:${local.account}:snapshot:${local.name}-drill-*",
        ]
      },
      {
        Sid    = "RdsDrillRestore" # restore a drill snapshot to the drill copy only
        Effect = "Allow"
        Action = ["rds:RestoreDBInstanceFromDBSnapshot", "rds:AddTagsToResource"]
        Resource = [
          "arn:aws:rds:${local.region}:${local.account}:db:${local.name}-drill",
          "arn:aws:rds:${local.region}:${local.account}:snapshot:${local.name}-drill-*",
          "arn:aws:rds:${local.region}:${local.account}:subgrp:${aws_db_subnet_group.main.name}",
          "arn:aws:rds:${local.region}:${local.account}:og:*",
          "arn:aws:rds:${local.region}:${local.account}:pg:*",
        ]
      },
      {
        Sid      = "RdsDrillDelete" # delete the drill copy, never production
        Effect   = "Allow"
        Action   = "rds:DeleteDBInstance"
        Resource = "arn:aws:rds:${local.region}:${local.account}:db:${local.name}-drill"
      },
    ]
  })
}

# ---------- EC2 admin host ----------
# AWS-managed policy: lets the SSM agent connect, so you can open a shell
# from the console without SSH keys or open ports.
resource "aws_iam_role" "ec2" {
  name = "${local.name}-ec2"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# An instance profile is how a role is attached to an EC2 instance.
resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name}-ec2"
  role = aws_iam_role.ec2.name
}

# ---------- Step Functions ----------
resource "aws_iam_role" "sfn" {
  name = "${local.name}-sfn"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "sfn" {
  name = "run-report-task"
  role = aws_iam_role.sfn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RunTask" # only the backend task definition
        Effect   = "Allow"
        Action   = "ecs:RunTask"
        Resource = "arn:aws:ecs:${local.region}:${local.account}:task-definition/${local.task_family}:*"
      },
      {
        Sid      = "WatchTask" # wait for the task to finish
        Effect   = "Allow"
        Action   = ["ecs:DescribeTasks", "ecs:StopTask"]
        Resource = "arn:aws:ecs:${local.region}:${local.account}:task/${local.cluster}/*"
      },
      {
        Sid      = "TaskEvents" # how Step Functions learns the task stopped
        Effect   = "Allow"
        Action   = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
        Resource = "arn:aws:events:${local.region}:${local.account}:rule/StepFunctionsGetEventsForECSTaskRule"
      },
      {
        Sid      = "PassTaskRoles" # hand the two ECS roles to the task
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = [aws_iam_role.ecs_execution.arn, aws_iam_role.ecs_task.arn]
      },
    ]
  })
}

# ---------- EventBridge Scheduler ----------
resource "aws_iam_role" "scheduler" {
  name = "${local.name}-scheduler"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "scheduler.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "start-report"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "states:StartExecution"
      Resource = "arn:aws:states:${local.region}:${local.account}:stateMachine:${local.state_machine}"
    }]
  })
}

# Phase B step 7: the restart workflow (Step Functions, jobs.tf)
# may force a new deployment of the backend service, and nothing else.
resource "aws_iam_role_policy" "sfn_restart" {
  name = "restart-backend"
  role = aws_iam_role.sfn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ecs:UpdateService"
      Resource = "arn:aws:ecs:${local.region}:${local.account}:service/${local.cluster}/${local.service}"
    }]
  })
}

# EventBridge rules (jobs.tf) use this role to start the restart workflow,
# and only that workflow.
resource "aws_iam_role" "events" {
  name = "${local.name}-events"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "events.amazonaws.com" }
      Condition = { StringEquals = { "aws:SourceAccount" = local.account } }
    }]
  })
}

resource "aws_iam_role_policy" "events" {
  name = "start-restart"
  role = aws_iam_role.events.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "states:StartExecution"
      Resource = aws_sfn_state_machine.restart.arn
    }]
  })
}
