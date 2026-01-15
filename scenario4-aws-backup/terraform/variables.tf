# ============================================================================
# VARIABLES
# All configurable parameters for the module
# ============================================================================

# --- Basic Configuration ---

variable "environment" {
  description = "Environment name (prod, staging, dev)"
  type        = string
  default     = "prod"
}

variable "backup_vault_name" {
  description = "Base name for backup vaults"
  type        = string
  default     = "allianz-backup-vault"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# --- KMS Keys ---
# Required in each region where we have a vault

variable "kms_key_arn" {
  description = "KMS key ARN in Frankfurt for encrypting backups"
  type        = string
}

variable "kms_key_arn_ireland" {
  description = "KMS key ARN in Ireland for encrypting DR backups"
  type        = string
}

# --- Resource Selection ---
# Tags that resources must have to be backed up

variable "backup_tag_key" {
  description = "Tag key to identify resources for backup"
  type        = string
  default     = "ToBackup"
}

variable "backup_tag_value" {
  description = "Tag value to identify resources for backup"
  type        = string
  default     = "true"
}

variable "owner_tag_value" {
  description = "Owner tag value to filter resources"
  type        = string
  default     = "owner@eulerhermes.com"
}

# --- Scheduling ---

variable "backup_schedule" {
  description = "Cron expression for daily backup (AWS format)"
  type        = string
  default     = "cron(0 3 * * ? *)" # Daily at 3 AM
}

# --- Retention ---

variable "retention_days" {
  description = "Days to keep local daily backups"
  type        = number
  default     = 35
}

variable "cross_region_retention_days" {
  description = "Retention days for copies in Ireland"
  type        = number
  default     = 35
}

variable "cross_account_retention_days" {
  description = "Retention days in Backup account (longer for security)"
  type        = number
  default     = 90
}

# --- Cross-region ---

variable "cross_region_destination" {
  description = "Destination region for DR copies"
  type        = string
  default     = "eu-west-1" # Ireland
}

# --- Cross-account ---

variable "backup_account_id" {
  description = "AWS account ID dedicated to backups"
  type        = string
}

variable "backup_account_vault_arn" {
  description = "Vault ARN in the backup account"
  type        = string
}

# --- Vault Lock (WORM) ---

variable "vault_lock_min_retention_days" {
  description = "Minimum days a backup must exist before deletion"
  type        = number
  default     = 7
}

variable "vault_lock_max_retention_days" {
  description = "Maximum allowed retention days"
  type        = number
  default     = 365
}

variable "vault_lock_changeable_days" {
  description = "Grace period before lock becomes permanent (to fix errors)"
  type        = number
  default     = 3
}
