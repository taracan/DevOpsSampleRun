# jobs.tf: the nightly report pipeline (EventBridge Scheduler + Step Functions).
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
