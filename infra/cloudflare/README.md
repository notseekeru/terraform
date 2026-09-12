# Cloudflare module — declarative DNS (`infra/cloudflare`)

Provider: `cloudflare/cloudflare` (≥5). State lives in R2 under
`terraform/cloudflare/terraform.tfstate` (see root `README.md`).

## Status (adopted)

The `seekeru.tech` zone (id `5a1a5f826d5a3398dc78ba360e24dfa0`) is managed.
The following tunnel hostnames are **imported into state and now tracked by
Terraform** (config mirrors them in `variables.tf` → `records`):

| Map key      | FQDN                      | Target (tunnel)              | Proxied |
| ------------ | ------------------------- | ---------------------------- | ------- |
| `apex`       | `seekeru.tech`            | `7bbbb5d4-…cfargotunnel.com` | yes     |
| `portfolio`  | `portfolio.seekeru.tech`  | `7bbbb5d4-…cfargotunnel.com` | yes     |
| `diagram`    | `diagram.seekeru.tech`    | `7bbbb5d4-…cfargotunnel.com` | yes     |
| `maxterview` | `maxterview.seekeru.tech` | `7bbbb5d4-…cfargotunnel.com` | yes     |

`terraform plan MOD=cloudflare` should report **No changes** against live DNS.

**Out of scope (not managed by this module — owned elsewhere):**
Clerk SaaS records (`accounts`, `clerk`, `clk._domainkey`, `clkmail`, …), and the
AWS ALB `alb.seekeru.tech` + its ACM validation CNAME, which live in the `infra/aws`
module (it creates its own Cloudflare records via an aliased `cloudflare` provider).

## Credentials

The provider is authenticated with `TF_VAR_CLOUDFLARE_API_TOKEN` — a
`cfat_…` API token with `Zone → DNS → Edit`. (`TF_VAR_CLOUDFLARE_ACCOUNT_ID` is
also stored in Infisical, but the DNS-only code path here does not consume it; it
is kept for parity/future tunnel work.) Inject via Infisical `/terraform` — never
commit token values.

## Workflow

Add, change, or remove hostnames by editing the `records` map in
`variables.tf`, then:

```bash
make init MOD=cloudflare     # first time / backend + provider
make plan MOD=cloudflare     # propose the DNS diff
make apply MOD=cloudflare    # apply it
```

- **Add** → new map entry (key, `type="CNAME"`, `name` relative to zone or `"@"`
  for apex, `content` = tunnel/CNAME target, `proxied=true` optionally `ttl`).
- **Change** → edit the value/name.
- **Remove** → delete the entry. Terraform deletes the record on `apply`.

## Adopting a future dashboard-created record

If you (or another tool) create a record in the dashboard that you now want
Terraform to own, it must be imported before config lands, or the apply will
try to duplicate it:

1. Identify the record id:
   `curl -s -H "Authorization: Bearer $TF_VAR_CLOUDFLARE_API_TOKEN" \
"https://api.cloudflare.com/client/v4/zones/<ZONE_ID>/dns_records"` (or the
   dashboard).
2. Add the matching entry to `records` in `variables.tf`.
3. Import it into state:
   ```bash
   infisical run --path /consumers/terraform --env dev -- terraform -chdir=infra/cloudflare import \
     'cloudflare_dns_record.this["<key>"]' '<ZONE_ID>/<RECORD_ID>'
   ```
4. `make plan MOD=cloudflare` → should show no diff.

## Zone settings / rules

`var.zone_settings` is wired to `cloudflare_zone_setting` (per-setting) but is
**empty by default** — nothing is asserted until you add entries, so live zone
settings are untouched. Only add a setting after confirming the current value
in the dashboard, or apply will revert it.
