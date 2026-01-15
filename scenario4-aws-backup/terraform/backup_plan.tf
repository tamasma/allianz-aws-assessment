# ============================================================================
# BACKUP PLAN
# Three backup levels: daily, weekly, and monthly
# Each with copy to Ireland and to the Backup account
# ============================================================================

resource "aws_backup_plan" "main" {
  name = "allianz-backup-plan-${var.environment}"

  # -------------------------------------------------------------------------
  # DAILY BACKUP
  # For quick recovery of recent changes
  # Runs every night at 3 AM
  # -------------------------------------------------------------------------
  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = var.backup_schedule
    start_window      = 60  # 1 hour to start
    completion_window = 180 # 3 hours to complete

    lifecycle {
      delete_after = var.retention_days
    }

    # Copy to Ireland for regional DR
    copy_action {
      destination_vault_arn = aws_backup_vault.secondary.arn

      lifecycle {
        delete_after = var.cross_region_retention_days
      }
    }

    # Copy to Backup account for total isolation
    copy_action {
      destination_vault_arn = var.backup_account_vault_arn

      lifecycle {
        delete_after = var.cross_account_retention_days
      }
    }

    recovery_point_tags = {
      Environment = var.environment
      BackupType  = "daily"
      ManagedBy   = "terraform"
    }
  }

  # -------------------------------------------------------------------------
  # WEEKLY BACKUP
  # Every Sunday at 4 AM, with 3-month retention
  # Useful for recovering states from weeks ago
  # -------------------------------------------------------------------------
  rule {
    rule_name         = "weekly-backup"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 4 ? * SUN *)"
    start_window      = 60
    completion_window = 180

    lifecycle {
      delete_after = 90 # 3 months
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.secondary.arn

      lifecycle {
        delete_after = 90
      }
    }

    copy_action {
      destination_vault_arn = var.backup_account_vault_arn

      lifecycle {
        delete_after = 180 # 6 months in Backup account
      }
    }

    recovery_point_tags = {
      Environment = var.environment
      BackupType  = "weekly"
      ManagedBy   = "terraform"
    }
  }

  # -------------------------------------------------------------------------
  # MONTHLY BACKUP
  # First day of each month at 5 AM
  # For audits and compliance - 1-year retention
  # -------------------------------------------------------------------------
  rule {
    rule_name         = "monthly-backup"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 5 1 * ? *)"
    start_window      = 60
    completion_window = 180

    lifecycle {
      delete_after = 365 # 1 full year
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.secondary.arn

      lifecycle {
        delete_after = 365
      }
    }

    copy_action {
      destination_vault_arn = var.backup_account_vault_arn

      lifecycle {
        delete_after = 365
      }
    }

    recovery_point_tags = {
      Environment = var.environment
      BackupType  = "monthly"
      ManagedBy   = "terraform"
    }
  }

  # For Windows EC2, use VSS for consistent backups
  advanced_backup_setting {
    backup_options = {
      WindowsVSS = "enabled"
    }
    resource_type = "EC2"
  }

  tags = merge(var.tags, {
    Name        = "allianz-backup-plan-${var.environment}"
    Environment = var.environment
  })
}
