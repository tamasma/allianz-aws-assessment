# ============================================================================
# MAIN CONFIGURATION
# Providers for Frankfurt (primary) and Ireland (DR)
# ============================================================================

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

# Primary provider - Frankfurt
provider "aws" {
  region = "eu-central-1"

  default_tags {
    tags = {
      Project     = "allianz-backup"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}

# Secondary provider for Ireland (DR)
provider "aws" {
  alias  = "ireland"
  region = "eu-west-1"

  default_tags {
    tags = {
      Project     = "allianz-backup"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}

# Data sources for current account info
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}
