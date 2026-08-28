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

resource "aws_sns_topic_subscription" "billing_alert_email" {
  topic_arn = aws_sns_topic.billing_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
