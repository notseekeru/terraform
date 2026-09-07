provider "aws" {
  region = "ap-southeast-1"

  # No endpoints.s3 override is needed here. The R2 remote-state endpoint is now
  # supplied to the backend via the per-module backend.tfbackend.tpl (rendered
  # at init into infra/aws/.terraform/backend.generated.tfbackend), so nothing
  # injects AWS_ENDPOINT_URL_S3 into this provider's environment at plan/apply.
  # Real aws_s3_bucket / aws_s3_bucket_policy calls therefore resolve to real AWS
  # S3 by default. If you ever reintroduce an ambient R2 endpoint env var here,
  # you must re-add an endpoints.s3 pin to real S3 (see
  # docs/incident-2026-08-27-r2-backend-credential-conflict.md).

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
