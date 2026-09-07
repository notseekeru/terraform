# Generated backend config for the `aws` module.
# Committed as a template: `__R2_ACCOUNT_ID__` is substituted at init-time from
# the Infisical secret $TF_VAR_R2_ACCOUNT_ID. Nothing here is secret.
bucket      = "terraform-state"
key         = "terraform/aws/terraform.tfstate"
region      = "auto"
use_lockfile = true

skip_region_validation      = true
skip_credentials_validation = true
skip_requesting_account_id  = true

endpoints = {
  s3 = "https://__R2_ACCOUNT_ID__.r2.cloudflarestorage.com"
}
