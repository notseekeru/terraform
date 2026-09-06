# Cloudflare API token. Scoped Zone:DNS:Edit + Zone:Read (min) on the managed
# zones. Inject via infisical as TF_VAR_CLOUDFLARE_API_TOKEN — never commit it.
variable "CLOUDFLARE_API_TOKEN" {
  type      = string
  sensitive = true
}

# Zones this module manages. Records reference one by its map key.
variable "zones" {
  type = map(object({
    zone_id = string # Cloudflare zone ID for data lookup / record import
  }))
  default = {
    seekeru = {
      zone_id = "5a1a5f826d5a3398dc78ba360e24dfa0"
    }
  }
}

# Explicit DNS records, one per map entry. Add a record here, plan, apply.
variable "records" {
  type = map(object({
    zone_key = string
    type     = string              # CNAME | A | TXT | ...
    name     = string              # relative to zone; "@" for the apex
    content  = string              # record payload (CNAME target, A addr, TXT)
    ttl      = optional(number, 1) # 1 = automatic (proxy-friendly)
    proxied  = optional(bool, false)
  }))
  default = {
    # Names are relative to the zone; @ = apex (seekeru.tech). All four point
    # at the cloudflared tunnel (UUID from the live CF Records list).
    apex = {
      zone_key = "seekeru"
      type     = "CNAME"
      name     = "@"
      content  = "7bbbb5d4-0fbc-469d-bbfe-a1de34559a3d.cfargotunnel.com"
      proxied  = true
    }
    portfolio = {
      zone_key = "seekeru"
      type     = "CNAME"
      name     = "portfolio"
      content  = "7bbbb5d4-0fbc-469d-bbfe-a1de34559a3d.cfargotunnel.com"
      proxied  = true
    }
    diagram = {
      zone_key = "seekeru"
      type     = "CNAME"
      name     = "diagram"
      content  = "7bbbb5d4-0fbc-469d-bbfe-a1de34559a3d.cfargotunnel.com"
      proxied  = true
    }
    max = {
      zone_key = "seekeru"
      type     = "CNAME"
      name     = "max"
      content  = "7bbbb5d4-0fbc-469d-bbfe-a1de34559a3d.cfargotunnel.com"
      proxied  = true
    }
  }
}

# Optional declarative zone settings, per-zone. Leave empty to touch nothing.
variable "zone_settings" {
  description = "Per-zone settings as cloudflare_zone_setting entries: setting_id (e.g. \"ssl\", \"http2\") + value. Empty => no-op."
  type = map(object({
    setting_id = string
    value      = string
    # Example: "portfolio-ssl" = { setting_id = "ssl", value = "strict" }
    # Do NOT add settings until you confirm the current dashboard value,
    # otherwise apply reverts live config.
  }))
  default = {}
}
