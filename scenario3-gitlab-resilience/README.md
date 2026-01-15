# Scenario 3: Resilience and Monitoring - GitLab Service

## Current Architecture

As shown in the diagram:
- Single EC2 instance running GitLab in a VPC
- Root volume on EBS
- Projects and artifacts on separate EBS volume
- RDS database with Multi-AZ enabled

---

## Question 1: What are the weaknesses of the current GitLab architecture from a resilience perspective?

### Single Points of Failure

1. **Single EC2 instance**: If this instance fails, GitLab is completely unavailable until manually recovered.

2. **Single Availability Zone**: All components except RDS are in one AZ. An AZ outage takes down the entire service.

3. **EBS storage limitation**: EBS volumes are replicated within a single AZ only - no protection against AZ failure.

4. **No automatic failover**: Instance failures require manual intervention to restore service.

5. **No horizontal scaling**: Cannot add capacity during high demand periods (e.g., before releases).

6. **No application health checks**: If GitLab hangs but the instance remains running, the problem goes undetected.

---

## Question 2: What target architecture do you suggest to improve resiliency?

### Target Architecture: Multi-AZ with Automatic Failover

```
                    ┌─────────────────────────────────┐
                    │          Route 53               │
                    │    (Health Checks + Failover)   │
                    └───────────────┬─────────────────┘
                                    │
                    ┌───────────────▼─────────────────┐
                    │   Application Load Balancer     │
                    │     (Multi-AZ, Health Checks)   │
                    └───────────────┬─────────────────┘
                                    │
           ┌────────────────────────┼────────────────────────┐
           │                        │                        │
  ┌────────▼────────┐     ┌────────▼────────┐     ┌────────▼────────┐
  │     AZ-1        │     │     AZ-2        │     │     AZ-3        │
  │  ┌──────────┐   │     │  ┌──────────┐   │     │  ┌──────────┐   │
  │  │ GitLab   │   │     │  │ GitLab   │   │     │  │ GitLab   │   │
  │  │ (ASG)    │   │     │  │ (ASG)    │   │     │  │ (Standby)│   │
  │  └──────────┘   │     │  └──────────┘   │     │  └──────────┘   │
  └─────────────────┘     └─────────────────┘     └─────────────────┘
           │                        │
           └──────────┬─────────────┘
                      │
         ┌────────────▼────────────┐
         │      Amazon EFS        │
         │   (Multi-AZ, Encrypted) │
         │   - Git repositories    │
         │   - Artifacts           │
         │   - Shared config       │
         └────────────┬────────────┘
                      │
         ┌────────────▼────────────┐
         │   RDS PostgreSQL       │
         │ (Multi-AZ + Read Replica)│
         └─────────────────────────┘
```

### Key Components

**EFS for Shared Storage** - Replace EBS with EFS for multi-AZ access:

```hcl
resource "aws_efs_file_system" "gitlab" {
  creation_token = "gitlab-efs"
  encrypted      = true
  kms_key_id     = var.kms_key_arn

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
}

resource "aws_efs_mount_target" "gitlab" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.gitlab.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}
```

**Auto Scaling Group** - Automatic instance replacement:

```hcl
resource "aws_autoscaling_group" "gitlab" {
  name                = "gitlab-asg"
  desired_capacity    = 2
  max_size            = 4
  min_size            = 2
  target_group_arns   = [aws_lb_target_group.gitlab.arn]
  vpc_zone_identifier = var.private_subnet_ids
  health_check_type   = "ELB"

  launch_template {
    id      = aws_launch_template.gitlab.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }
}
```

**Application Load Balancer** - Traffic distribution and health checks:

```hcl
resource "aws_lb_target_group" "gitlab" {
  name     = "gitlab-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/-/health"
    timeout             = 5
    unhealthy_threshold = 3
  }
}
```

---

## Question 3: What monitoring practices would you implement on GitLab?

### Infrastructure Monitoring with CloudWatch Alarms

```hcl
# CPU utilization
resource "aws_cloudwatch_metric_alarm" "gitlab_cpu" {
  alarm_name          = "gitlab-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.gitlab.name
  }
}

# Memory (requires CloudWatch Agent)
resource "aws_cloudwatch_metric_alarm" "gitlab_memory" {
  alarm_name          = "gitlab-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "mem_used_percent"
  namespace           = "CWAgent"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# EFS burst credits
resource "aws_cloudwatch_metric_alarm" "efs_burst_credits" {
  alarm_name          = "gitlab-efs-burst-credits-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  threshold           = 1000000000
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FileSystemId = aws_efs_file_system.gitlab.id
  }
}

# ALB unhealthy hosts
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "gitlab-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    TargetGroup  = aws_lb_target_group.gitlab.arn_suffix
    LoadBalancer = aws_lb.gitlab.arn_suffix
  }
}
```

### Synthetic Monitoring with CloudWatch Synthetics

```python
def handler(event, context):
    import requests

    endpoints = [
        "https://gitlab.example.com/-/health",
        "https://gitlab.example.com/-/readiness",
        "https://gitlab.example.com/-/liveness"
    ]

    for endpoint in endpoints:
        response = requests.get(endpoint, timeout=10)
        if response.status_code != 200:
            raise Exception(f"Health check failed: {endpoint}")

    return "All health checks passed"
```

---

## Question 4: How would you automate the runbook of GitLab?

### SSM Automation Document for GitLab Upgrades

```yaml
schemaVersion: '0.3'
description: Automated GitLab upgrade runbook
assumeRole: '{{AutomationAssumeRole}}'

parameters:
  TargetVersion:
    type: String
    description: Target GitLab version
  AutoScalingGroupName:
    type: String
    description: GitLab ASG name

mainSteps:
  # Step 1: Create backup before upgrade
  - name: CreateBackup
    action: aws:executeAwsApi
    inputs:
      Service: backup
      Api: StartBackupJob
      BackupVaultName: gitlab-vault
      ResourceArn: '{{EFSArn}}'
      IamRoleArn: '{{BackupRoleArn}}'

  # Step 2: Wait for backup completion
  - name: WaitForBackup
    action: aws:waitForAwsResourceProperty
    inputs:
      Service: backup
      Api: DescribeBackupJob
      BackupJobId: '{{CreateBackup.BackupJobId}}'
      PropertySelector: State
      DesiredValues:
        - COMPLETED

  # Step 3: Update Launch Template with new AMI
  - name: UpdateLaunchTemplate
    action: aws:executeScript
    inputs:
      Runtime: python3.8
      Handler: update_ami
      Script: |
        def update_ami(events, context):
            import boto3
            ec2 = boto3.client('ec2')
            # Update launch template with new GitLab AMI

  # Step 4: Rolling update
  - name: RollingUpdate
    action: aws:executeAwsApi
    inputs:
      Service: autoscaling
      Api: StartInstanceRefresh
      AutoScalingGroupName: '{{AutoScalingGroupName}}'
      Strategy: Rolling
      Preferences:
        MinHealthyPercentage: 50
        InstanceWarmup: 300

  # Step 5: Verify health
  - name: VerifyHealth
    action: aws:executeScript
    inputs:
      Runtime: python3.8
      Handler: verify_health
      Script: |
        def verify_health(events, context):
            import requests
            response = requests.get("https://gitlab.example.com/-/health")
            assert response.status_code == 200
```

### Scheduled Maintenance with EventBridge

```hcl
resource "aws_cloudwatch_event_rule" "gitlab_maintenance" {
  name                = "gitlab-weekly-maintenance"
  schedule_expression = "cron(0 3 ? * SUN *)"  # Sundays at 3 AM
}

resource "aws_cloudwatch_event_target" "maintenance_automation" {
  rule      = aws_cloudwatch_event_rule.gitlab_maintenance.name
  target_id = "GitLabMaintenance"
  arn       = aws_ssm_document.gitlab_maintenance.arn
  role_arn  = aws_iam_role.eventbridge_ssm.arn
}
```

### Configuration Management with Parameter Store

```hcl
resource "aws_ssm_parameter" "gitlab_config" {
  name  = "/gitlab/config/gitlab.rb"
  type  = "SecureString"
  value = file("${path.module}/gitlab.rb")
}
```

Instances pull configuration at boot time:

```bash
#!/bin/bash
aws ssm get-parameter --name "/gitlab/config/gitlab.rb" --with-decryption \
  --query "Parameter.Value" --output text > /etc/gitlab/gitlab.rb

gitlab-ctl reconfigure
```
