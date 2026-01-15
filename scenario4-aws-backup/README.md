# Scenario 4: Backup Policy - Terraform Module for AWS Backup

## Requirements

Implement a Terraform module for AWS Backup with:

1. **Plan definition**: Including backup policy (daily, weekly, monthly) and lifecycle policy
2. **Resource selection**: By tags
3. **Cross-Region copy**: Frankfurt → Ireland
4. **Cross-Account copy**: To dedicated Backup account
5. **WORM protection**: Vault Lock on backup vaults

---

## Architecture

```
┌─────────────────┐     ┌─────────────────────────────────────────┐
│ Backup Module   │     │           Production Account            │
│                 │     │  ┌─────────┐  ┌─────────┐               │
│ - Plan          │────▶│  │Frankfurt│  │ Ireland │               │
│ - Selection     │     │  │ Vault   │  │ Vault   │               │
│                 │     │  │(Locked) │  │(Locked) │               │
└─────────────────┘     │  └─────────┘  └─────────┘               │
                        └─────────────────┬───────────────────────┘
                                          │ Cross-Account Copy
                        ┌─────────────────▼───────────────────────┐
                        │            Backup Account               │
                        │  ┌─────────────────┐                    │
                        │  │   Frankfurt     │                    │
                        │  │   Vault (Locked)│                    │
                        │  └─────────────────┘                    │
                        └─────────────────────────────────────────┘
```

---

## Module Structure

```
terraform/
├── main.tf              # Providers and data sources
├── variables.tf         # Configurable variables
├── outputs.tf           # ARNs and IDs for other modules
├── backup_vault.tf      # Vaults in Frankfurt and Ireland with Lock
├── backup_plan.tf       # Backup rules (daily, weekly, monthly)
├── backup_selection.tf  # Resource selection by tags
└── iam.tf               # IAM permissions for AWS Backup
```

---

## Implementation Details

### 1. Plan Definition (Daily, Weekly, Monthly with Lifecycle)

```hcl
resource "aws_backup_plan" "main" {
  name = "backup-plan-${var.environment}"

  # Daily backup - 35 days retention
  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 3 * * ? *)"

    lifecycle {
      delete_after = var.retention_days
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.secondary.arn
      lifecycle {
        delete_after = var.cross_region_retention_days
      }
    }

    copy_action {
      destination_vault_arn = var.backup_account_vault_arn
      lifecycle {
        delete_after = var.cross_account_retention_days
      }
    }
  }

  # Weekly backup
  rule {
    rule_name         = "weekly-backup"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 4 ? * SUN *)"

    lifecycle {
      delete_after = var.retention_days
    }
  }

  # Monthly backup
  rule {
    rule_name         = "monthly-backup"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 5 1 * ? *)"

    lifecycle {
      delete_after = var.cross_account_retention_days
    }
  }
}
```

### 2. Resource Selection by Tags

```hcl
resource "aws_backup_selection" "tagged_resources" {
  name         = "tagged-resources-selection"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn

  # AND logic: both tags must match
  selection_tag {
    type  = "STRINGEQUALS"
    key   = var.backup_tag_key      # ToBackup
    value = var.backup_tag_value    # true
  }

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Owner"
    value = var.owner_tag_value
  }
}
```

### 3. Cross-Region Copy (Frankfurt → Ireland)

```hcl
# Secondary vault in Ireland
resource "aws_backup_vault" "secondary" {
  provider = aws.ireland
  name     = "${var.backup_vault_name}-dr"
  kms_key_arn = var.kms_key_arn_ireland
}

# Copy action in backup plan rule
copy_action {
  destination_vault_arn = aws_backup_vault.secondary.arn
  lifecycle {
    delete_after = var.cross_region_retention_days
  }
}
```

### 4. Cross-Account Copy

```hcl
# Copy to dedicated Backup account
copy_action {
  destination_vault_arn = var.backup_account_vault_arn
  lifecycle {
    delete_after = var.cross_account_retention_days
  }
}
```

### 5. WORM Protection (Vault Lock)

```hcl
resource "aws_backup_vault_lock_configuration" "primary" {
  backup_vault_name   = aws_backup_vault.primary.name
  min_retention_days  = var.vault_lock_min_retention_days
  max_retention_days  = var.vault_lock_max_retention_days
  changeable_for_days = var.vault_lock_changeable_days
}

resource "aws_backup_vault_lock_configuration" "secondary" {
  provider            = aws.ireland
  backup_vault_name   = aws_backup_vault.secondary.name
  min_retention_days  = var.vault_lock_min_retention_days
  max_retention_days  = var.vault_lock_max_retention_days
  changeable_for_days = var.vault_lock_changeable_days
}
```

---

## Usage

```hcl
module "backup" {
  source = "./terraform"

  environment              = "prod"
  backup_vault_name        = "allianz-backup-vault"
  kms_key_arn              = "arn:aws:kms:eu-central-1:123456789:key/xxx"
  kms_key_arn_ireland      = "arn:aws:kms:eu-west-1:123456789:key/yyy"
  backup_account_id        = "987654321"
  backup_account_vault_arn = "arn:aws:backup:eu-central-1:987654321:backup-vault:central"

  # Retention
  retention_days               = 35
  cross_region_retention_days  = 35
  cross_account_retention_days = 90

  # Vault Lock
  vault_lock_min_retention_days = 7
  vault_lock_max_retention_days = 365
  vault_lock_changeable_days    = 3

  tags = {
    Project = "allianz-backup"
  }
}
```

---

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `backup_schedule` | Cron for daily backups | `cron(0 3 * * ? *)` |
| `retention_days` | Local retention days | 35 |
| `cross_region_destination` | DR region | `eu-west-1` |
| `vault_lock_changeable_days` | Grace period before immutability | 3 |

---

## Outputs

- `backup_vault_arn` - Primary vault ARN (Frankfurt)
- `secondary_vault_arn` - Secondary vault ARN (Ireland)
- `backup_plan_arn` - Backup plan ARN
- `backup_role_arn` - IAM role used by AWS Backup
