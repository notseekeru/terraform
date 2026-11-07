provider "aws" {
  region = var.region

  # The R2 state backend is reached through the ambient AWS_ENDPOINT_URL_S3, which the s3
  # backend reads on every run. That same variable would route aws_s3_bucket calls to R2,
  # which rejects real AWS keys, so this pin keeps bucket resources pointed at AWS.
  # Do not unset the variable around plan/apply: it would starve the backend instead.
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
