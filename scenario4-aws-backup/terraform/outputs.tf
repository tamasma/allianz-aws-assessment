# ============================================================================
# OUTPUTS
# Exported values for other modules to use
# ============================================================================

# --- Vaults ---

output "backup_vault_arn" {
  description = "ARN of the primary vault in Frankfurt"
  value       = aws_backup_vault.primary.arn
}

output "backup_vault_name" {
  description = "Name of the primary vault"
  value       = aws_backup_vault.primary.name
}

output "secondary_vault_arn" {
  description = "ARN of the DR vault in Ireland"
  value       = aws_backup_vault.secondary.arn
}

# --- Backup Plan ---

output "backup_plan_id" {
  description = "ID of the backup plan"
  value       = aws_backup_plan.main.id
}

output "backup_plan_arn" {
  description = "ARN of the backup plan"
  value       = aws_backup_plan.main.arn
}

# --- IAM ---

output "backup_role_arn" {
  description = "ARN of the IAM role used by AWS Backup"
  value       = aws_iam_role.backup.arn
}

# --- Selections ---

output "backup_selection_ids" {
  description = "Backup selection IDs by resource type"
  value = {
    tagged_resources = aws_backup_selection.tagged_resources.id
    rds              = aws_backup_selection.rds_databases.id
    dynamodb         = aws_backup_selection.dynamodb_tables.id
    s3               = aws_backup_selection.s3_buckets.id
  }
}
