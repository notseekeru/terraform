provider "aws" {
  region = "ap-southeast-1"

  # The R2 state-backend endpoint is delivered via the ambient AWS_ENDPOINT_URL_S3
  # env var, which the s3 backend needs present on EVERY run (init AND plan/apply) to
  # reach R2 for remote state. That same var would otherwise ALSO route
  # aws_s3_bucket/aws_s3_bucket_policy calls to R2 (which rejects real AWS AKIA keys:
  # 'access key has length 20, should be 32'). This pin is therefore the SOLE thing
  # that keeps real bucket resources pointed at AWS while the endpoint var is present.
  # Do not `unset AWS_ENDPOINT_URL_S3` around plan/apply/refresh/destroy — that would
  # starve the backend's own R2 connection (s3 backend would fall back to AWS S3 DNS).
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

# Cloudflare provider (aliased) backs this module's own DNS records so the ALB hostname
# (alb.seekeru.tech) and its ACM-validation CNAME auto-issue in one `apply` — no dashboard.
# Uses the same TF_VAR_CLOUDFLARE_API_TOKEN as the infra/cloudflare module.
provider "cloudflare" {
  alias     = "cf"
  api_token = var.CLOUDFLARE_API_TOKEN
}
