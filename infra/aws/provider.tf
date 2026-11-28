provider "aws" {
  region = var.region

  # No AWS_* endpoint setting is needed: state is in Postgres, so nothing hands an R2
  # address to this provider. The pin stays as the guard if one ever reappears in the
  # environment, and it keeps aws_s3_bucket* resources in AWS.
  endpoints {
    s3 = "https://s3.${var.region}.amazonaws.com"
  }

  default_tags {
    tags = {
      Project     = "sesume"
      ManagedBy   = "Terraform"
      Environment = "Prod"
    }
  }
}

provider "cloudflare" {
  alias     = "cf"
  api_token = var.CLOUDFLARE_API_TOKEN
}
