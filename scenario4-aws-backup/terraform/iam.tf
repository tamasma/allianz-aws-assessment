# ============================================================================
# IAM PERMISSIONS
# Role used by AWS Backup to perform its operations
# Uses AWS managed policies plus custom policy for cross-account
# ============================================================================

# Main AWS Backup role
resource "aws_iam_role" "backup" {
  name = "aws-backup-role-${var.environment}"

  # Only AWS Backup can assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# AWS managed policy for creating backups
# Includes permissions for EC2, RDS, DynamoDB, EFS, etc.
resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# AWS managed policy for restoring backups
resource "aws_iam_role_policy_attachment" "restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# S3 requires specific policies
resource "aws_iam_role_policy_attachment" "s3_backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup"
}

resource "aws_iam_role_policy_attachment" "s3_restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Restore"
}

# Custom policy for cross-account copies
# Managed policies don't cover this
resource "aws_iam_role_policy" "cross_account_copy" {
  name = "cross-account-backup-copy"
  role = aws_iam_role.backup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCrossAccountCopy"
        Effect = "Allow"
        Action = [
          "backup:CopyIntoBackupVault",
          "backup:StartCopyJob"
        ]
        Resource = [
          var.backup_account_vault_arn,
          aws_backup_vault.secondary.arn
        ]
      },
      {
        # For cross-account we need to use KMS keys from both regions
        Sid    = "AllowKMSForCrossAccount"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:ReEncrypt*",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = [
          var.kms_key_arn,
          var.kms_key_arn_ireland
        ]
      }
    ]
  })
}
