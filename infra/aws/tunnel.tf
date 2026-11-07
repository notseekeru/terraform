# A second, independent tunnel. The k3s one (server-tunnel) is owned by cloudflared and gitops
# and is declared in infra/cloudflare; nothing here reads or adopts it.
resource "cloudflare_zero_trust_tunnel_cloudflared" "sesume" {
  provider = cloudflare.cf

  account_id = var.CLOUDFLARE_ACCOUNT_ID
  name       = "sesume"
  config_src = "cloudflare"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "sesume" {
  provider = cloudflare.cf

  account_id = var.CLOUDFLARE_ACCOUNT_ID
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.sesume.id
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "sesume" {
  provider = cloudflare.cf

  account_id = var.CLOUDFLARE_ACCOUNT_ID
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.sesume.id

  config = {
    ingress = [
      { hostname = var.domain, service = "http://localhost:8080" },
      { service = "http_status:404" },
    ]
  }
}

resource "cloudflare_dns_record" "sesume" {
  provider = cloudflare.cf

  zone_id = var.cloudflare_zone_id
  name    = var.domain
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.sesume.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}
