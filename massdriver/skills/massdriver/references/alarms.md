# Adding Alarms to Bundles

Massdriver integrates cloud-native alarms for visibility in the UI. See [Monitoring and Alarms Guide](https://docs.massdriver.cloud/guides/monitoring-and-alarms) for full documentation.

## AWS CloudWatch (Recommended Approach)

Use the Massdriver Terraform modules for simplified alarm setup:
- [aws/alarm-channel](https://github.com/massdriver-cloud/terraform-modules/tree/main/aws/alarm-channel) - Creates SNS topic for alarm notifications
- [aws/cloudwatch-alarm](https://github.com/massdriver-cloud/terraform-modules/tree/main/aws/cloudwatch-alarm) - Creates CloudWatch alarm + registers with Massdriver

```hcl
# src/alarms.tf

# 1. Create alarm channel (SNS topic) - one per bundle
module "alarm_channel" {
  source      = "github.com/massdriver-cloud/terraform-modules//aws/alarm-channel?ref=main"
  md_metadata = var.md_metadata
}

# 2. Create alarms using the channel
module "alarm_high_cpu" {
  source      = "github.com/massdriver-cloud/terraform-modules//aws/cloudwatch-alarm?ref=main"
  md_metadata = var.md_metadata

  alarm_name   = "${var.md_metadata.name_prefix}-high-cpu"
  display_name = "High CPU Utilization"
  message      = "RDS CPU utilization is above 80%"

  namespace   = "AWS/RDS"
  metric_name = "CPUUtilization"
  statistic   = "Average"
  period      = "300"

  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  threshold           = "80"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  sns_topic_arn = module.alarm_channel.arn
}
```

**Module benefits:**
- Handles SNS topic creation and Massdriver webhook subscription
- Automatically registers `massdriver_package_alarm` for UI visibility
- Consistent alarm naming and tagging

## GCP Cloud Monitoring

```hcl
resource "google_monitoring_alert_policy" "high_cpu" {
  display_name = "${var.md_metadata.name_prefix}-high-cpu"
  combiner     = "OR"

  conditions {
    display_name = "CPU Utilization > 80%"
    condition_threshold {
      filter          = "resource.type=\"cloudsql_database\" AND metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
    }
  }

  notification_channels = [google_monitoring_notification_channel.massdriver.id]
}

resource "google_monitoring_notification_channel" "massdriver" {
  display_name = "Massdriver Webhook"
  type         = "webhook_tokenauth"
  labels = {
    url = var.md_metadata.observability.alarm_webhook_url
  }
}

resource "massdriver_package_alarm" "high_cpu" {
  display_name      = "High CPU Utilization"
  cloud_resource_id = google_monitoring_alert_policy.high_cpu.name

  metric {
    name      = "cloudsql.googleapis.com/database/cpu/utilization"
    statistic = "Average"
  }

  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  period_minutes      = 5
}
```

## Azure Monitor

```hcl
resource "azurerm_monitor_metric_alert" "high_cpu" {
  name                = "${var.md_metadata.name_prefix}-high-cpu"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_postgresql_flexible_server.main.id]
  description         = "CPU utilization is above 80%"

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.massdriver.id
  }
}

resource "azurerm_monitor_action_group" "massdriver" {
  name                = "${var.md_metadata.name_prefix}-massdriver"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "massdriver"

  webhook_receiver {
    name        = "massdriver"
    service_uri = var.md_metadata.observability.alarm_webhook_url
  }
}

resource "massdriver_package_alarm" "high_cpu" {
  display_name      = "High CPU Utilization"
  cloud_resource_id = azurerm_monitor_metric_alert.high_cpu.id

  metric {
    namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    name      = "cpu_percent"
    statistic = "Average"
  }

  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  period_minutes      = 5
}
```

## cloudwatch-alarm Module Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `md_metadata` | Yes | Massdriver metadata variable |
| `alarm_name` | Yes | CloudWatch alarm name |
| `display_name` | Yes | Label shown in Massdriver UI |
| `message` | Yes | Alarm description |
| `sns_topic_arn` | Yes | SNS topic from alarm_channel module |
| `namespace` | Yes | AWS metric namespace (AWS/RDS, AWS/EC2, etc.) |
| `metric_name` | Yes | Metric name |
| `statistic` | Yes | Average, Sum, Maximum, etc. |
| `period` | Yes | Evaluation period in seconds |
| `comparison_operator` | Yes | GreaterThanThreshold, LessThanThreshold, etc. |
| `evaluation_periods` | Yes | Number of periods to evaluate |
| `threshold` | Yes | Alert trigger value |
| `dimensions` | Yes | Metric dimensions (map) |
