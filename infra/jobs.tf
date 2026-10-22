# jobs.tf: scheduled jobs (EventBridge Scheduler).
#
# 1. The nightly report pipeline (Scheduler + Step Functions), below.
# 2. Backend restarts so tasks pick up the rotated DB password (Phase B,
#    step 7), at the end of this file: right after each password change,
#    plus once a day as a safety net.
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
# Daily backend restart (Phase B, step 7)
#
# Why: RDS changes the database password every 7 days by itself
# (manage_master_user_password, data.tf). An ECS task reads DB_PASSWORD only
# when it STARTS, so a task that has been running since before a rotation
# still holds the old password. Connections it already has keep working,
# but every new login fails, and /api/v1/ready would report "db: error".
#
# Fix: restart the backend once a day, so tasks are never more than a day
# old and always start with the current password. A restart here is ECS's
# normal rolling deployment: a new task starts and must pass the load
# balancer's /health check before the old one stops, so the site stays up.
# Same task definition and image; nothing new is deployed.
#
#   EventBridge Scheduler (every day at 03:30 UTC, after the 02:00 report)
#        | calls the ECS API directly (no Lambda or Step Functions needed)
#        v
#   ecs:UpdateService --force-new-deployment on smallproject-backend
#
# Run it by hand: aws ecs update-service --cluster smallproject
#   --service smallproject-backend --force-new-deployment
# ---------------------------------------------------------------------------

resource "aws_scheduler_schedule" "restart" {
  name                = "${local.name}-daily-restart"
  schedule_expression = "cron(30 3 * * ? *)" # 03:30 UTC daily

  flexible_time_window {
    mode = "OFF"
  }

  target {
    # "Universal target": the Scheduler calls this AWS API action itself.
    arn      = "arn:aws:scheduler:::aws-sdk:ecs:updateService"
    role_arn = aws_iam_role.scheduler.arn
    input = jsonencode({
      Cluster            = local.cluster
      Service            = local.service
      ForceNewDeployment = true
    })
  }
}

# ---------------------------------------------------------------------------
# Restart right after each password change (Phase B, step 7 follow-up)
#
# The daily restart above can leave a gap of up to a day: RDS changes the
# password "some time during" the 7th day (no fixed time), and can change
# it early (e.g. "Rotate secret now" in the console). This closes the gap
# to a few minutes by reacting to the change itself:
#
#   Secrets Manager finishes a rotation of the DB secret
#        | emits "RotationSucceeded" (a CloudTrail service event, which
#        | EventBridge receives automatically, no trail needed)
#        v
#   EventBridge rule "smallproject-db-password-rotated"
#        | starts (EventBridge rules can't call ecs:UpdateService directly)
#        v
#   Step Functions "smallproject-restart": one step, ecs:UpdateService
#   --force-new-deployment on smallproject-backend (same rolling restart as
#   the daily one: no downtime)
#
# The daily 03:30 restart stays as a safety net in case an event is missed.
# Run it by hand: AWS console -> Step Functions -> smallproject-restart
#   -> Start execution.
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
