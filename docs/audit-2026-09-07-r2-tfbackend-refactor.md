# Audit — R2 Backend Endpoint Refactor (2026-09-07)

Scope: verify Option-2 refactor (R2 backend endpoint delivered via per-module
`.tfbackend` template instead of the ambient `AWS_ENDPOINT_URL_S3` env var), remove
the stale Infisical secret, and validate live state bindings.

## Status: PATCHED + LIVE-VERIFIED for backend rebinding; DATA-INCONSISTENCY found
## (aws/doks R2 state under-initialized) — do NOT apply aws/doks until reconciled.

---

## 1. Infisical secret cleanup

- Removed (shared, `/terraform`, dev): `AWS_ENDPOINT_URL_S3`. ✓ Confirmed gone.
- Confirmed still present (required): `TF_VAR_R2_ACCOUNT_ID`, `TF_VAR_R2_ACCESS_KEY_ID`,
  `TF_VAR_R2_BUCKET`, `TF_VAR_R2_SECRET_ACCESS_KEY`. ✓
- Observed leftovers (NOT removed, out of scope — flag only): `TF_VAR_SSH_PUBLIC_KEY`
  (repo prereq already dropped), `service_account_test` (looks like test debris).

## 2. Refactor validation (all four modules)

End-to-end verified that after `make reconfigure`,
`infra/<MOD>/.terraform/terraform.tfstate` (backend cache) now carries the R2
endpoint as a real config value, not an ambient env var:

| Module   | endpoints.s3 in cache                | Bound OK |
|----------|--------------------------------------|----------|
| aws      | `9ca4…fb6.r2.cloudflarestorage.com`  | ✓        |
| cloudflare| `9ca4…fb6.r2.cloudflarestorage.com` | ✓        |
| doks     | `9ca4…fb6.r2.cloudflarestorage.com`  | ✓        |
| k3s      | `9ca4…fb6.r2.cloudflarestorage.com`  | ✓        |

- The `provider.tf` `endpoints.s3` override ("bandaid") was removed from `infra/aws`.
- `make plan MOD=aws/…` runs with `unset AWS_ENDPOINT_URL_S3 AWS_ENDPOINT_URL AWS_S3_ENDPOINT`
  (Makefile `no_r2_endpoint` guard) so the AWS provider can never route to R2, even if a
  stale env secret is ever re-added.
- Canary `make plan MOD=cloudflare` → **No changes**, state intact.

## 3. Bug caught during live migration

Initial `make reconfigure` failed with "`Failed to read file … backend.generated.tfbackend`".
Cause: the `-backend-config` path was repo-root-relative, but `terraform -chdir=infra/<MOD>`
resolves it relative to the module dir. Fixed by consuming `.terraform/backend.generated.tfbackend`
(module-relative) in the terraform flags while the render script still writes
repo-root-relative. Amended into the refactor commit. Retest passed on all modules.

## 4. ⚠️ PRE-EXISTING R2 STATE INCONSISTENCY (not caused by this refactor)

After rebinding, `terraform state list` per module shows:

| Module   | R2 state content                                              | Interpretation            |
|----------|---------------------------------------------------------------|---------------------------|
| cloudflare| 4 `cloudflare_dns_record` + zone data (=5)                  | POPULATED ✓               |
| k3s      | 11 resources (helm, secrets, postgres statefulset, manifest)  | POPULATED ✓               |
| aws      | only `aws_availability_zones.available` + `aws_ssm_parameter` | 0 MANAGED RESOURCES       |
| doks     | (none) — "No state file was found"                            | EMPTY                     |

This contradicts AWS.md §"Deployed endpoints (as of this writing)" which documents live
`https://alb.seekeru.tech`, CloudFront `https://d14f3y8b1rk8te.cloudfront.net`, etc.
The likely cause: aws (and possibly doks) were applied under **local state** before the
R2 backend was enabled (`bf4ec98`), and the one-time `make migrate MOD=<m>` was never run
for them — so the R2 keys hold no managed state. git-ignored local `terraform.tfstate`
files that once held that applied state are gone (they are not in git).

### Consequence
Running `make plan MOD=aws` now reports "12 to add" (doks) / full add for aws as-if
undeployed. **`apply` on aws/doks would re-provision real AWS/DO resources and possibly
duplicate anything still running that is no longer tracked in R2 state.**

### Recommended resolution (YOUR decision — touches live cloud)
- If the live AWS/DO resources still exist and you want them under Terraform:
  1. Manually re-import the live resources into the aws module state (`terraform import`
     per resource from AWS.md's resource map), or
  2. Recover any pre-refactor local `terraform.tfstate` if still on a machine and
     `make migrate MOD=aws` it into R2.
- If the AWS/DO resources were already intentionally torn down (sandbox reset), then the
  empty state is correct and `apply` will just (re)build — confirm `make destroy`/
  nuke history first.
- `cloudflare` + `k3s` are verified safe and correct.

I did **not** run `apply`/`destroy` on any module. Only safe `reconfigure` + `plan`
were executed during this audit.

## 5. Commits
- `ae936a8` (amended): `ref(make)` deliver R2 backend endpoint via per-module tfbackend
  (templates, render script, versions.tf stubs, aws provider override removal, docs).
- `eeba8da`: `style` terraform fmt pre-existing alignment warnings.

## 6. Repo hygiene
- `.terraform.lock.hcl` still gitignored (pre-existing; noted earlier as drift vector).
- No generated `.tfbackend`/state file is tracked. Working tree clean.
