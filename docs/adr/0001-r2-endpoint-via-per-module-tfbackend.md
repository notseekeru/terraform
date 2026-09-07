# ADR 0001 — Deliver the R2 state-backend endpoint via per-module `.tfbackend`, not an ambient env var

- **Status:** Accepted (implemented 2026-09, live-verified on all four modules)
- **Date:** 2026-09-07
- **Supersedes:** the `endpoints.s3` provider override (the "bandaid") from the earlier R2/AWS credential-collision incident (`docs/incident-2026-08-27-r2-backend-credential-conflict.md`)
- **Related:** `Makefile`, `scripts/render-tfbackend.sh`, `infra/<MOD>/backend.tfbackend.tpl`

---

## Context

Every Terraform module uses **Cloudflare R2** as its S3-compatible remote-state backend.
Two modules also target real cloud providers (notably the `aws` module) via the same
Terraform process.

The failure mode is a namespace collision:

- The R2 **state backend** is an S3 API.
- The AWS **provider** is also an S3 API.
- Both read credentials/endpoints from the same ambient `AWS_*` environment namespace,
  and one process runs both.

Originally the R2 endpoint was injected as the global env var **`AWS_ENDPOINT_URL_S3`**
(the only non-deprecated way to point the s3 backend at a custom endpoint after the
`endpoint` backend key was deprecated). Because `infisical run` injected it into the
whole process, the AWS provider **also** read it and routed real `aws_s3_bucket` /
`aws_s3_bucket_policy` calls to R2 — producing `InvalidArgument: access key has length 20,
should be 32` against real AWS `AKIA` keys.

The first fix added an `endpoints { s3 = "https://s3.<region>.amazonaws.com" }` override
on the AWS provider to force it back to real AWS. This worked but was a **compensating
control fighting a symptom**: one shared knob meant two opposite things to two consumers.

### Constraints that shaped the decision

- The s3 backend reads its custom endpoint from the fixed name `AWS_ENDPOINT_URL_S3`
  (or `endpoints.s3` backend config). I cannot rename that variable or tell the backend to
  look elsewhere.
- The account id inside the R2 endpoint host (`https://<acct>.r2.cloudflarestorage.com`)
  is account-specific — it must not be hardcoded in the repo (reproducibility across
  devices/operators), so it stays a secret in Infisical (`TF_VAR_R2_ACCOUNT_ID`).
- Backend config is resolved at `init` and cached per module in `.terraform/`.

---

## Decision

**Remove the R2 endpoint from the ambient environment and deliver it to the s3 backend as
real, per-module backend config.**

1. Each module owns a committed, non-secret template `infra/<MOD>/backend.tfbackend.tpl`
   holding the structural backend config (`bucket`, `key`, `region`, `endpoints.s3`, the
   `skip_*`/`use_lockfile` flags). The R2 account id in `endpoints.s3` is a placeholder.
2. `scripts/render-tfbackend.sh` substitutes the account id from the Infisical secret
   `TF_VAR_R2_ACCOUNT_ID` at `init`-time, writing a gitignored `.tfbackend` into the
   module's `.terraform/`.
3. Only the two secret keys (`TF_VAR_R2_ACCESS_KEY_ID` / `TF_VAR_R2_SECRET_ACCESS_KEY`)
   are passed separately as `-backend-config` flags.
4. `make plan`/`apply`/`refresh`/`destroy` run through a guard that **`unset`s**
   `AWS_ENDPOINT_URL_S3`, `AWS_ENDPOINT_URL`, and `AWS_S3_ENDPOINT`, so the AWS provider
   never inherits an R2 endpoint even if a stale secret is ever re-added.
5. The stale `AWS_ENDPOINT_URL_S3` Infisical secret was removed.
6. Each `versions.tf` `backend "s3" {}` block was reduced to a stub; the `.tfbackend`
   template is the single source of truth for structural backend config.

### Old workflow vs. new workflow

| Step | Old | New |
| --- | --- | --- |
| Secret source | creds `TF_VAR_R2_*`; endpoint global `AWS_ENDPOINT_URL_S3` | creds `TF_VAR_R2_*`; endpoint in per-module `.tfbackend`, account id from `TF_VAR_R2_ACCOUNT_ID` |
| R2 endpoint → backend | ambient env var `AWS_ENDPOINT_URL_S3` | real `.tfbackend` value merged at `init` |
| AWS provider env at plan/apply | **sees** `AWS_ENDPOINT_URL_S3` (polluted) | endpoint vars **`unset`** (clean) |
| AWS provider S3 routing | needed `endpoints { s3 = … }` override | defaults to real AWS; no override |
| Structural backend config home | flat Makefile flag block + env | single `backend.tfbackend.tpl` per module |
| Adding a module | re-wire the implicit env trick | add one template + a stub block |
| Drifts back to R2 again? | yes, silently (until it errors) | no shared knob; plus defensive `unset` |

---

## Consequences

### Positive
- Collision removed **by construction**, not by override: no shared ambient variable that
  the backend and provider read for opposite purposes.
- Backend contract is explicit and self-contained per module; scales to new modules.
- Stays dynamic / operator-reproducible (account id still from Infisical; nothing secret or
  account-specific hardcoded in the repo).
- Defensive `unset` protects the provider even if `AWS_ENDPOINT_URL_S3` is later re-added.
- Live-verified: after `make reconfigure` on all four modules (aws, cloudflare, doks, k3s),
  each backend cache carries `endpoints.s3 = https://<acct>.r2.cloudflarestorage.com`,
  and `make plan MOD=cloudflare` reports **No changes**.

### Negative / trade-offs
- One extra moving part per module: a committed template + a render step at `init`
  (`scripts/render-tfbackend.sh`). Slightly more than the single env var it replaced.
- Generated `.tfbackend` filenames must be kept gitignored (they are, under `.terraform/`).
- The s3 `backend` key deprecation nuance meant the `-backend-config` path must be
  **module-relative** (after `-chdir=infra/<MOD>`); caught and fixed during migration.

### Risks
- If a future operator reintroduces an ambient `AWS_ENDPOINT_URL_S3` (or starts passing it
  in `.envrc`/Infisical), the AWS provider regresses to R2. Mitigated by the `unset` guard
  and by README/incident notes.
- k3s/cloudflare need no such guard (no AWS provider) but use the same mechanism for
  consistency.

---

## Alternatives considered (and rejected)

1. **Keep the ambient env var, scope it to `init` only.** Rejected: a single terraform process runs both backend and provider from one OS environment, so an ambient var can't be limited to one consumer. Observations during migration supported this: the endpoint only became durable (available to later plan/apply from the backend cache) when it was static backend config, so leaving it only in the init-time env was not reliable for plan/apply. It also keeps the endpoint in the ambient namespace. (Not a controlled negative test; rejected on architecture grounds + these observations.)
2. **Hardcode the account id in committed static `.tfbackend` files.** Rejected: makes the
   repo machine/account-specific, hurting the "operator-reproducible on a fresh clone" goal.
3. **Separate the R2 backend and real AWS provider into two separate Terraform
   configurations.** Cleanest in principle, but a much larger architectural change than
   this repo (single-owner, module-per-dir) needs.

---

## Migration / correctness notes (for future agents)

- Reproduce a fresh bind: `make reconfigure MOD=<m>`, then `make plan MOD=<m>` should be
  **No changes** (cloudflare/k3s are populated and authoritative; aws/doks R2 state may be
  under-initialized — see `docs/audit-2026-09-07-r2-tfbackend-refactor.md`; do not `apply`
  aws/doks until that state gap is resolved).
- The render script errors if `TF_VAR_R2_ACCOUNT_ID` is unset (preventing silently-broken
  endpoints).
- See the README "State Management" section and the operational audit for current status.
