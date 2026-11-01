# jobs.tf: scheduled jobs (EventBridge Scheduler).
#
# 1. The nightly report pipeline (Scheduler + Step Functions), below.
# 2. A backend restart right after each DB password change (Phase B,
#    step 7), at the end of this file.
#
#   EventBridge Scheduler (every night at 02:00 UTC)
#        | starts
#        v
#   Step Functions state machine "smallproject-report"
#        | runs, and waits for it to finish
#        v
#   ECS Fargate task: the SAME backend image, with the command changed to
#   `python -m app.report`
#        | writes
#        v
#   s3://smallproject-reports-<account>/reports/<date>.csv
#
# Why Step Functions instead of starting the task directly: it waits for
# the task, retries it if it fails (2 more tries, 1 then 2 minutes
# apart), and records every run with its status in the console.
# CloudWatch alarms on failed runs (monitoring.tf).
#
# Run it by hand: AWS console -> Step Functions -> smallproject-report
#   -> Start execution.
# The job's output goes to the same log group as the API
# (/ecs/smallproject-backend).
#
# Cost: a few cents a month (one short Fargate task per night).

resource "aws_sfn_state_machine" "report" {
  name     = local.state_machine
  role_arn = aws_iam_role.sfn.arn

  # Amazon States Language: a single step that runs an ECS task.
  definition = jsonencode({
    Comment = "Nightly registrations report"
    StartAt = "RunReport"
    States = {
      RunReport = {
        Type     = "Task"
        Resource = "arn:aws:states:::ecs:runTask.sync" # .sync = wait until the task stops
        Parameters = {
          LaunchType     = "FARGATE"
          Cluster        = aws_ecs_cluster.main.arn
          TaskDefinition = aws_ecs_task_definition.backend.arn
          NetworkConfiguration = {
            AwsvpcConfiguration = {
              Subnets        = aws_subnet.private[*].id
              SecurityGroups = [aws_security_group.ecs.id] # same access as the API: RDS, internet via NAT
              AssignPublicIp = "DISABLED"
            }
          }
          Overrides = {
            ContainerOverrides = [{
              Name    = "backend"
              Command = ["python", "-m", "app.report"]
            }]
          }
        }
        Retry = [{
          ErrorEquals     = ["States.ALL"]
          MaxAttempts     = 2
          IntervalSeconds = 60
          BackoffRate     = 2
        }]
        End = true
      }
    }
  })
}

resource "aws_scheduler_schedule" "report" {
  name                = "${local.name}-nightly-report"
  schedule_expression = "cron(0 2 * * ? *)" # 02:00 UTC daily

  flexible_time_window {
    mode = "OFF" # run at exactly that time
  }

  target {
    arn      = aws_sfn_state_machine.report.arn
    role_arn = aws_iam_role.scheduler.arn
  }
}

# ---------------------------------------------------------------------------
# Restart right after each DB password change (Phase B, step 7)
#
# Why: RDS changes the database password every 7 days by itself
# (manage_master_user_password, data.tf), at no fixed time on that day, and
# can change it early (e.g. "Rotate secret now"). An ECS task reads
# DB_PASSWORD only when it STARTS, so the running task keeps the old
# password: connections it already has keep working, but every new login
# fails and /api/v1/ready reports "db: error".
#
# Fix: restart the backend as soon as the change is done, about once a week.
# A restart is ECS's normal rolling deployment: a new task (which reads the
# new password) must pass the load balancer's /health check before the old
# one stops. Same image and settings; nothing new is deployed.
#
#   Secrets Manager finishes a rotation of the DB secret
#        | emits "RotationSucceeded", an "AWS Service Event via CloudTrail".
#        | EventBridge only receives those because a CloudTrail trail
#        | exists (trail.tf). Without it, this never fired (2026-10-22).
#        v
#   EventBridge rule "smallproject-db-password-rotated"
#        | starts (EventBridge rules can't call ecs:UpdateService directly)
#        v
#   Step Functions "smallproject-restart": one step, ecs:UpdateService
#   --force-new-deployment on smallproject-backend
#
# Expect a few minutes of "db: error" per change: the database switches to
# the new password shortly before RotationSucceeded, and the rolling restart
# takes about 4 minutes. AWS delivers these events "on a best effort basis",
# so if one is ever missed, run the restart by hand:
#   AWS console -> Step Functions -> smallproject-restart -> Start execution
# ---------------------------------------------------------------------------

resource "aws_sfn_state_machine" "restart" {
  name     = "${local.name}-restart"
  role_arn = aws_iam_role.sfn.arn

  definition = jsonencode({
    Comment = "Rolling restart of the backend service (new tasks read the current DB password)"
    StartAt = "Restart"
    States = {
      Restart = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:ecs:updateService"
        Parameters = {
          Cluster            = local.cluster
          Service            = local.service
          ForceNewDeployment = true
        }
        End = true
      }
    }
  })
}

# Matches the real event recorded on 2026-10-19 (CloudTrail):
# eventName RotationSucceeded, additionalEventData.SecretId = the DB secret.
resource "aws_cloudwatch_event_rule" "db_password_rotated" {
  name        = "${local.name}-db-password-rotated"
  description = "The RDS master password was rotated: restart the backend"
  event_pattern = jsonencode({
    source        = ["aws.secretsmanager"]
    "detail-type" = ["AWS Service Event via CloudTrail"]
    detail = {
      eventSource         = ["secretsmanager.amazonaws.com"]
      eventName           = ["RotationSucceeded"]
      additionalEventData = { SecretId = [aws_db_instance.main.master_user_secret[0].secret_arn] }
    }
  })
}

resource "aws_cloudwatch_event_target" "db_password_rotated" {
  rule     = aws_cloudwatch_event_rule.db_password_rotated.name
  arn      = aws_sfn_state_machine.restart.arn
  role_arn = aws_iam_role.events.arn
}
