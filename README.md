# Allianz Trade - AWS Cloud Engineer Skills Assessment

## Scenarios

### Scenario 1: Encryption Management - KMS Key Rotation
- Challenges and impacts of key rotation with BYOK
- Steps for applying key rotation
- Monitoring non-compliant resources with AWS Config
- Securing key material transportation from HSM to KMS

### Scenario 2: APIs-as-a-Product - Public and Private APIs
- Architecture weaknesses analysis
- New architecture for public/private API separation
- CloudFront path-based routing configuration
- APIGW protection from CloudFront bypass

### Scenario 3: Resilience & Monitoring - GitLab Service
- Current architecture weaknesses
- Target HA architecture with ASG, EFS, ALB
- CloudWatch monitoring implementation
- Runbook automation with SSM

### Scenario 4: Backup Policy - AWS Backup (Terraform Module)
- Complete Terraform module implementation
- Plan definition (frequency, retention, encryption)
- Resource selection by tags
- Cross-region and cross-account copy
- Vault Lock (WORM protection)

## Repository Structure
```
allianz-aws-assessment/
├── README.md
├── scenario1-kms-rotation/
│   └── README.md
├── scenario2-api-architecture/
│   └── README.md
├── scenario3-gitlab-resilience/
│   └── README.md
└── scenario4-aws-backup/
    ├── README.md
    └── terraform/
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        ├── backup_plan.tf
        ├── backup_vault.tf
        ├── backup_selection.tf
        └── iam.tf
```

## Usage (Scenario 4 - Terraform)
```bash
cd scenario4-aws-backup/terraform
terraform init
terraform plan -var-file="prod.tfvars"
terraform apply -var-file="prod.tfvars"
```
