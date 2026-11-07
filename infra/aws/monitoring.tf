resource "aws_sns_topic" "alerts" {
  name = "sesume-alerts"
}

resource "aws_sns_topic_subscription" "alert_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.ALERT_EMAIL
}

resource "aws_budgets_budget" "zero_spend" {
  name              = "sesume-zero-spend"
  budget_type       = "COST"
  limit_amount      = "1.0"
  limit_unit        = "USD"
  time_period_start = "2024-01-01_00:00"
  time_unit         = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_budgets_budget" "credit_cap" {
  name              = "sesume-credit-cap"
  budget_type       = "COST"
  limit_amount      = tostring(var.credit_cap_usd)
  limit_unit        = "USD"
  time_period_start = "2024-01-01_00:00"
  time_unit         = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 95
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 90
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = aws_lambda_function.this

  alarm_name          = "sesume-${each.key}-errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = { FunctionName = each.value.function_name }
}

resource "aws_cloudwatch_metric_alarm" "review_dlq" {
  alarm_name          = "sesume-review-dlq"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = { QueueName = aws_sqs_queue.review_dlq.name }
}

resource "aws_cloudwatch_metric_alarm" "edge_status" {
  count = length(aws_instance.edge)

  alarm_name          = "sesume-edge-status"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = { InstanceId = aws_instance.edge[0].id }
}
