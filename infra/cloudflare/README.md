# Module-scoped README: adopting Cloudflare DNS as declarative infra.

## Why
`portfolio.seekeru.tech` and `diagram.seekeru.tech` (plus any AWS ALB host) are
currently registered in the Cloudflare dashboard. This module makes those DNS
records + zone config code: add a map entry, `make plan`, `make apply`. No
dashboard round-trips for DNS.

## Credentials (ZERO-TOUCH — never through an agent)
An API token scoped `Zone:DNS:Edit` on `seekeru.tech` is required. Store it in
Infisical as `CLOUDFLARE_ACCESS_TOKEN` (or whatever the Makefile target expects)
and export `TF_VAR_CLOUDFLARE_API_TOKEN` in the infisical env. Do not copy it
into the repo.

## One-time adoption — import existing records BEFORE first apply
Live hostnames must be imported into state so an apply does not delete/duplicate
them.

1. Get the zone id (dashboard → zone → Overview, or `zone_id` below).
2. List live DNS record ids: `curl https://api.cloudflare.com/client/v4/zones/<ZONE>/dns_records?name=seekeru.tech`
   (or read them from the dashboard).
3. For each record to manage, fetch its `<RECORD_ID>` and import (v5 resource
   name is `cloudflare_dns_record`):
   ```
   make init MOD=cloudflare
   terraform -chdir=infra/cloudflare import \
     'cloudflare_dns_record.this["<key>"]' '<ZONE_ID>/<RECORD_ID>'
   ```
4. Populate that record's map entry below so config matches state.
   `make plan` should then show no diff.

## Adding a record later
```
records = {
  "portfolio" = { zone_key="seekeru", type="CNAME", name="portfolio",
                  content="<tunnel>.cfargotunnel.com", proxied=true }
}
```
then `make plan MOD=cloudflare && make apply MOD=cloudflare`.
