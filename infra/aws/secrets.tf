locals {
  ssm_prefix = "/sesume"
  # RDS rejects an unencrypted session. pg treats sslmode=require as verify-full, which fails
  # against RDS's CA, so uselibpqcompat asks for libpq's meaning: encrypt, do not verify.
  database_url = "postgresql://${aws_db_instance.main.username}:${urlencode(var.POSTGRES_PASSWORD)}@${aws_db_instance.main.address}:5432/${aws_db_instance.main.db_name}?uselibpqcompat=true&sslmode=require"
}

# The functions read these at cold start (see backend/src/bootstrap.ts); the edge instance
# reads the tunnel and origin tokens at boot. Nothing is injected as Lambda env.
resource "aws_ssm_parameter" "app" {
  for_each = {
    database_url = local.database_url
    auth_secret  = var.AUTH_SECRET
    data_key     = var.DATA_KEY
    origin_token = var.ORIGIN_TOKEN
    tunnel_token = data.cloudflare_zero_trust_tunnel_cloudflared_token.sesume.token
  }

  name  = "${local.ssm_prefix}/${each.key}"
  type  = "SecureString"
  value = each.value
}
