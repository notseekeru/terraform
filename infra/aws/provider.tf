provider "aws" {
  region = "ap-southeast-1"

  # AWS_ENDPOINT_URL_S3 points at Cloudflare R2 for the remote-state backend. Without
  # this override the provider would ALSO route aws_s3_bucket calls to R2 (which rejects
  # real AWS AKIA keys with 'credential key has length 20, should be 32'). Pin the
  # provider to real AWS S3 so bucket resources land in AWS, not R2.
  endpoints {
    s3 = "https://s3.ap-southeast-1.amazonaws.com"
  }

  # Standard tags for cost tracking and identification
  default_tags {
    tags = {
      Project     = "Personal-AWS-Sandbox"
      ManagedBy   = "Terraform"
      Environment = "Dev"
    }
  }
}
