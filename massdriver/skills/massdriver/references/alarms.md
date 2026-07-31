# Adding Alarms to Bundles

Massdriver surfaces cloud-native alarms in the UI. Use the official Massdriver modules — each cloud has an **alarm-channel** module (creates the notification plumbing to Massdriver's webhook, one per bundle) and a **metric-alarm** module (creates the cloud alarm AND registers it with the instance via `massdriver_instance_alarm`, one per alarm).

Full input documentation lives in each module's README:

| Cloud | Modules | Alarm modes |
|-------|---------|-------------|
| AWS | [aws-alarm-channel](https://github.com/massdriver-cloud/terraform-massdriver-aws-alarm-channel) / [aws-metric-alarm](https://github.com/massdriver-cloud/terraform-massdriver-aws-metric-alarm) | Simple metric, or metric-math expressions (`metric_queries` + `display_metric_key`) |
| GCP | [gcp-alarm-channel](https://github.com/massdriver-cloud/terraform-massdriver-gcp-alarm-channel) / [gcp-metric-alarm](https://github.com/massdriver-cloud/terraform-massdriver-gcp-metric-alarm) | Boolean, or numeric threshold (with `aggregations`) |
| Azure | [azure-alarm-channel](https://github.com/massdriver-cloud/terraform-massdriver-azure-alarm-channel) / [azure-metric-alarm](https://github.com/massdriver-cloud/terraform-massdriver-azure-metric-alarm) | Static threshold, or dynamic threshold (Azure ML, `dynamic_criteria`) |

All metric-alarm modules require the massdriver provider `>= 2.0`.

## AWS

```hcl
# src/alarms.tf
module "alarm_channel" {
  source      = "massdriver-cloud/aws-alarm-channel/massdriver"
  md_metadata = var.md_metadata
}

module "cpu_alarm" {
  source = "massdriver-cloud/aws-metric-alarm/massdriver"

  md_metadata   = var.md_metadata
  sns_topic_arn = module.alarm_channel.arn

  alarm_name   = "${var.md_metadata.name_prefix}-cpu-high"
  display_name = "CPU High"
  message      = "CPU utilization exceeded threshold"

  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  threshold           = 80

  metric_name = "CPUUtilization"
  namespace   = "AWS/RDS"
  period      = 300
  statistic   = "Average"
  dimensions  = { DBInstanceIdentifier = aws_db_instance.main.identifier }
}
```

## GCP

```hcl
module "alarm_channel" {
  source      = "massdriver-cloud/gcp-alarm-channel/massdriver"
  md_metadata = var.md_metadata
}

module "cpu_alarm" {
  source = "massdriver-cloud/gcp-metric-alarm/massdriver"

  md_metadata             = var.md_metadata
  notification_channel_id = module.alarm_channel.id

  display_name  = "High CPU"
  message       = "CPU utilization is above 80%"
  metric_type   = "cloudsql.googleapis.com/database/cpu/utilization"
  resource_type = "cloudsql_database"
  comparison    = "COMPARISON_GT"
  threshold     = 0.8
  duration      = 60

  aggregations = {
    alignment_period     = 60
    per_series_aligner   = "ALIGN_MAX"
    cross_series_reducer = "REDUCE_MEAN"
  }
}
```

## Azure

```hcl
module "alarm_channel" {
  source      = "massdriver-cloud/azure-alarm-channel/massdriver"
  md_metadata = var.md_metadata
}

module "cpu_alarm" {
  source = "massdriver-cloud/azure-metric-alarm/massdriver"

  md_metadata             = var.md_metadata
  monitor_action_group_id = module.alarm_channel.id
  resource_group_name     = azurerm_resource_group.main.name
  scopes                  = [azurerm_postgresql_flexible_server.main.id]

  alarm_name   = "${var.md_metadata.name_prefix}-cpu-high"
  display_name = "CPU High"
  message      = "CPU utilization exceeded threshold"

  severity    = 2
  frequency   = "PT5M"
  window_size = "PT15M"

  metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
  metric_name      = "cpu_percent"
  aggregation      = "Average"
  operator         = "GreaterThanOrEqual"
  threshold        = 80
}
```

## Custom alarms (no module)

For providers or cases the modules don't cover, the underlying pattern is: a cloud alarm that notifies `var.md_metadata.observability.alarm_webhook_url`, plus a `massdriver_instance_alarm` resource registering it with the instance (`display_name`, `cloud_resource_id`, optional `comparison_operator`/`threshold`/`period`/`metric` block — see the provider docs for the schema). `instance_id` is inferred automatically inside a Massdriver deployment.
