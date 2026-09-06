# Purpose: pull Cloudflare DNS under Terraform control so records are
# declared in this repo and applied via plan, not punched into the dashboard.
#
# Scope today = DNS records. The two live k3s hostnames are reached through
# a cloudflared tunnel that registers its own routes from a token + gitops
# ingress (see ~/gitops/infra/cloudflared.yaml). That tunnel identity is owned
# by cloudflared, NOT by Terraform — do not model cloudflare_tunnel here or
# you'll fight the running tunnel. If you ever want Terraform to own the
# tunnel/intranet DNS itself, that is a separate tunnel-config adoption effort;
# cloudflare_tunnel + cloudflare_tunnel_config is the documented way.

# Zone data sources keyed by the zone name. zone_id comes from var.zones.
locals {
  zone_by_key = {
    for zk, z in var.zones : zk => data.cloudflare_zone.by_key[zk]
  }
}

data "cloudflare_zone" "by_key" {
  for_each = var.zones
  zone_id  = var.zones[each.key].zone_id
}

# Explicit DNS records, declared in var.records. provider v5 resource is
# cloudflare_dns_record; the record payload is `content` (not `value`).
resource "cloudflare_dns_record" "this" {
  for_each = var.records

  zone_id = local.zone_by_key[each.value.zone_key].id
  name    = each.value.name    # "portfolio" or "@" for apex (relative to zone)
  type    = each.value.type    # CNAME | A | TXT | ...
  content = each.value.content # e.g. "<tunnel-uuid>.cfargotunnel.com"
  ttl     = each.value.ttl
  proxied = each.value.proxied
}

# Optional zone settings (provider v5 style: one cloudflare_zone_setting per
# setting, keyed by Cloudflare setting_id). Empty var.zone_settings => no-op.
resource "cloudflare_zone_setting" "this" {
  for_each = {
    for zk, zs in var.zone_settings : "${zk}:${zs.setting_id}" => merge(zs, { zone_key = zk })
  }

  zone_id    = local.zone_by_key[each.value.zone_key].id
  setting_id = each.value.setting_id
  value      = each.value.value
}
