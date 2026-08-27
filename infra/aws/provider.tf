provider "aws" {
  region = "ap-southeast-1"

  # Standard tags for cost tracking and identification
  default_tags {
    tags = {
      Project     = "Personal-AWS-Sandbox"
      ManagedBy   = "Terraform"
      Environment = "Dev"
    }
  }
}
