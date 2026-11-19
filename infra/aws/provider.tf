provider "aws" {
  region = var.region

  # No AWS_* endpoint setting is needed: the R2 endpoint reaches the s3 backend as a
  # -backend-config flag at init and is stored with the rest of the backend config.
  # This pin stays as the guard if one ever reappears in the environment; it keeps
  # aws_s3_bucket* resources in AWS.
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
