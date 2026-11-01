# monitoring.tf: CloudWatch alarms.
#
# CloudWatch already collects, with no setup:
#   - Logs: the API and the nightly job write to /ecs/smallproject-backend
#     (log group in app.tf). Console: CloudWatch -> Log groups.
#   - Metrics: every AWS service publishes numbers automatically (ALB
#     requests and errors, ECS CPU, RDS connections, Step Functions runs).
#
# An alarm watches one metric and changes state (OK -> ALARM) when it
# crosses a threshold. Two alarms here:
#   - backend-5xx:   the backend returned server errors (HTTP 500-599)
#   - report-failed: a nightly report run failed even after its retries
#
# "No data" counts as OK (treat_missing_data), because no traffic or no
# runs is normal. The alarms have no notification attached; you see
# them in: CloudWatch -> Alarms.
#
# Cost: 2 standard alarms are within the free tier (10 alarms).

resource "aws_cloudwatch_metric_alarm" "backend_5xx" {
  alarm_name          = "${local.name}-backend-5xx"
  alarm_description   = "Backend returned 5xx errors through the load balancer"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = aws_lb.main.arn_suffix }
  statistic           = "Sum"
  period              = 300 # 5 minutes
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "report_failed" {
  alarm_name          = "${local.name}-report-failed"
  alarm_description   = "Nightly report Step Functions execution failed"
  namespace           = "AWS/States"
  metric_name         = "ExecutionsFailed"
  dimensions          = { StateMachineArn = aws_sfn_state_machine.report.arn }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
}
