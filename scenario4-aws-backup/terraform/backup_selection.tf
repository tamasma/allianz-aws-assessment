# ============================================================================
# RESOURCE SELECTION
# Which resources get backed up - using tags for granular control
# Only resources with ToBackup=true AND Owner=owner@eulerhermes.com
# ============================================================================

# General selection by tags
# Multiple selection_tag blocks create AND logic (all must match)
resource "aws_backup_selection" "tagged_resources" {
  name         = "tagged-resources-selection"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn

  # First filter: resource must have ToBackup=true
  selection_tag {
    type  = "STRINGEQUALS"
    key   = var.backup_tag_key
    value = var.backup_tag_value
  }

  # Second filter: AND must have correct Owner
  # Prevents accidentally backing up other teams' resources
  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Owner"
    value = var.owner_tag_value
  }
}

# Specific selection for RDS databases
resource "aws_backup_selection" "rds_databases" {
  name         = "rds-databases-selection"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn

  # Only RDS instances
  resources = ["arn:aws:rds:*:*:db:*"]

  selection_tag {
    type  = "STRINGEQUALS"
    key   = var.backup_tag_key
    value = var.backup_tag_value
  }

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Owner"
    value = var.owner_tag_value
  }
}

# Selection for DynamoDB tables
resource "aws_backup_selection" "dynamodb_tables" {
  name         = "dynamodb-tables-selection"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = ["arn:aws:dynamodb:*:*:table/*"]

  selection_tag {
    type  = "STRINGEQUALS"
    key   = var.backup_tag_key
    value = var.backup_tag_value
  }

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Owner"
    value = var.owner_tag_value
  }
}

# Selection for S3 buckets
# Note: S3 backup requires versioning enabled on the bucket
resource "aws_backup_selection" "s3_buckets" {
  name         = "s3-buckets-selection"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = ["arn:aws:s3:::*"]

  selection_tag {
    type  = "STRINGEQUALS"
    key   = var.backup_tag_key
    value = var.backup_tag_value
  }

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Owner"
    value = var.owner_tag_value
  }
}
