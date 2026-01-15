# ============================================================================
# BACKUP VAULTS
# Two vaults: one in Frankfurt (primary) and one in Ireland (DR)
# Both with Vault Lock enabled for WORM protection
# ============================================================================

# Primary vault in Frankfurt - all backups go here first
resource "aws_backup_vault" "primary" {
  name        = "${var.backup_vault_name}-${var.environment}"
  kms_key_arn = var.kms_key_arn

  tags = merge(var.tags, {
    Name        = "${var.backup_vault_name}-${var.environment}"
    Environment = var.environment
  })
}

# Vault Lock - makes backups immutable (WORM)
# After grace period (changeable_for_days), even admins cannot delete
resource "aws_backup_vault_lock_configuration" "primary" {
  backup_vault_name   = aws_backup_vault.primary.name
  min_retention_days  = var.vault_lock_min_retention_days
  max_retention_days  = var.vault_lock_max_retention_days
  changeable_for_days = var.vault_lock_changeable_days
}

# Vault in Ireland for disaster recovery
# If Frankfurt goes down, data is available here
resource "aws_backup_vault" "secondary" {
  provider    = aws.ireland
  name        = "${var.backup_vault_name}-${var.environment}-dr"
  kms_key_arn = var.kms_key_arn_ireland

  tags = merge(var.tags, {
    Name        = "${var.backup_vault_name}-${var.environment}-dr"
    Environment = var.environment
    Purpose     = "disaster-recovery"
  })
}

# Vault Lock in Ireland - same WORM protection
resource "aws_backup_vault_lock_configuration" "secondary" {
  provider            = aws.ireland
  backup_vault_name   = aws_backup_vault.secondary.name
  min_retention_days  = var.vault_lock_min_retention_days
  max_retention_days  = var.vault_lock_max_retention_days
  changeable_for_days = var.vault_lock_changeable_days
}

# Policy to allow Backup account to copy here
# Required for cross-account copy
resource "aws_backup_vault_policy" "primary" {
  backup_vault_name = aws_backup_vault.primary.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCrossAccountCopy"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.backup_account_id}:root"
        }
        Action = [
          "backup:CopyIntoBackupVault"
        ]
        Resource = "*"
      }
    ]
  })
}
