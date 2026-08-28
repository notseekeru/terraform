resource "aws_sns_topic" "billing_alerts" {
  name = "billing-alerts"
}

resource "aws_budgets_budget" "zero_spend" {
  name              = "zero-spend-budget"
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
    subscriber_sns_topic_arns = [aws_sns_topic.billing_alerts.arn]
  }
}

resource "aws_budgets_budget" "credit_cap" {
  # Guards the ~$200 free-tier credit balance: alerts before the
  # promotional credits are exhausted, distinct from the zero-spend guardrail.
  name              = "credit-cap-budget"
  budget_type       = "COST"
  limit_amount      = tostring(var.credit_cap_usd)
  limit_unit        = "USD"
  time_period_start = "2024-01-01_00:00"
  time_unit         = "MONTHLY"

  notification {
    # Actual spend hits the credit cap
    comparison_operator       = "GREATER_THAN"
    threshold                 = 95
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.billing_alerts.arn]
  }

  notification {
    # Projected spend about to exceed the credit cap
    comparison_operator       = "GREATER_THAN"
    threshold                 = 90
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.billing_alerts.arn]
  }
}

resource "aws_sns_topic_subscription" "billing_alert_email" {
  topic_arn = aws_sns_topic.billing_alerts.arn
  protocol  = "email"
  endpoint  = var.ALERT_EMAIL
}

resource "aws_cloudwatch_metric_alarm" "asg_cpu" {
  alarm_name          = "asg-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }

  alarm_actions = [aws_sns_topic.billing_alerts.arn]
}
