# ADR 0001 — R2 state-backend endpoint via ambient env var + provider pin

- **Status:** Accepted (2026-09-07, revised — reverts the earlier per-module `.tfbackend` iteration)
- **Date:** 2026-09-07
- **Supersedes:** the per-module `backend.tfbackend.tpl` + `scripts/render-tfbackend.sh` mechanism
  (which itself superseded the `endpoints.s3` provider override after the R2/AWS collision
  incident, `docs/incident-2026-08-27-r2-backend-credential-conflict.md`)
- **Related:** `Makefile`, `infra/<MOD>/versions.tf` (`backend "s3"` blocks), `infra/aws/provider.tf`

---

## Decision history (why this ADR now says what it says)

| Date | Decision | Status |
| --- | --- | --- |
| 2026-08 | Deliver the R2 endpoint via ambient `AWS_ENDPOINT_URL_S3` + an `endpoints.s3` provider pin (the incident-era fix). | **Superseded** by 2026-09-07 |
| 2026-09-07 | Deliver via per-module `backend.tfbackend.tpl` rendered by `render-tfbackend.sh` (ADR 0001 first version); drop the provider pin. | **Reverted** on 2026-09-08 |
| **2026-09-08** | **Current:** ambient `AWS_ENDPOINT_URL_S3` present on all runs + `endpoints.s3` pin in `provider.tf` (flat, no tpl/render layer). | **Accepted** |

**Why the per-module iteration was reverted (2026-09-08):** it was over-engineered for a
single-owner sandbox — one committed template + a render script + `TFBACKEND_OUT(_REL)`
Makefile plumbing per module just to deliver one non-secret endpoint URL (YAGNI). It also
moved structural backend config out of the canonical `versions.tf` `backend "s3"` block into a
parallel template, splitting configuration across two sources of truth. The real incident fix
was never the template — it is cred namespacing (`TF_VAR_R2_*`) plus, in the flat design, the
`provider.tf` `endpoints.s3` pin; a live `make plan MOD=k3s` also proved the endpoint var must
stay present on every run (an `unset` guard broke the backend's own R2 connection).

---

## Context

Every Terraform module uses **Cloudflare R2** as its S3-compatible remote-state backend.
The `aws` module additionally provisions into real AWS through the same Terraform process.
R2 and AWS are both S3 APIs, so both the s3 *backend* and the AWS *provider* read the same
ambient `AWS_*` environment namespace — one namespace, two opposite consumers.

Terraform ≥1.5 rejects the deprecated `endpoint` `-backend-config` key, so the only
non-deprecated ways to point the s3 backend at a custom R2 endpoint are (a) the ambient
env var `AWS_ENDPOINT_URL_S3` (mapped to the backend's `endpoints.s3`) or (b) real static
backend config delivered at `init`.

An earlier iteration (ADR 0001 first version) chose (b) via **per-module `.tfbackend`
templates** rendered at `init` by a shell script — an account-id placeholder substituted
from the `TF_VAR_R2_ACCOUNT_ID` Infisical secret. It removed the collision by construction
and let `provider.tf` drop its `endpoints.s3` pin. It was live-verified on all four modules.

### Why that iteration is being reverted

- It added **one committed template + a render script + Makefile path plumbing per module**
  (`infra/<MOD>/backend.tfbackend.tpl`, `.terraform/backend.generated.tfbackend`,
  `TFBACKEND_OUT(_REL)` juggling). For a personal sandbox that is disproportionate
  complexity to deliver a single endpoint URL. Reuse/YAGNI favor the ambient var that
  Terraform already reads natively.
- It moved structural backend config out of the natural `versions.tf` `backend "s3"` block
  into a parallel template file, splitting configuration across two sources of truth.

### What the revision keeps / what the live test corrected

The real incident fix was never the template — it was **namespacing R2 creds as
`TF_VAR_R2_*`** so they cannot shadow the AWS provider creds. A first draft of this
revision also kept a mutate-time `unset` of the R2 endpoint vars, but a live `make plan
MOD=k3s` proved that wrong: the s3 backend reads the endpoint from `AWS_ENDPOINT_URL_S3`
on **every** run (not just `init`), so `unset` made it fall back to `*.s3.auto.amazonaws.com`
and fail. The endpoint var must stay present on all targets; the provider pin is therefore
the sole safeguard. The per-module render layer is dropped as unnecessary indirection.

## Decision

**Deliver the R2 endpoint as the ambient `AWS_ENDPOINT_URL_S3`, present on every terraform
run, keep structural backend settings inline in each `versions.tf`, and pin the AWS
provider to real S3.** The `aws` provider pin is what stops the shared endpoint var from
routing AWS bucket resources to R2 — do not try to remove that var from mutate-time envs.

1. Each module's `versions.tf` keeps a real inline `backend "s3"` block (`skip_*` +
   `use_lockfile`). `bucket`, `key`, `region`, and the two secret creds are supplied as
   `-backend-config` flags in the Makefile (init-style targets run through `/bin/sh -c` so
   the `$TF_VAR_R2_*` refs expand from infisical's injected env), expanding from the
   `TF_VAR_R2_*` secrets.
2. The R2 endpoint is the ambient `AWS_ENDPOINT_URL_S3` env var, which Terraform maps to
   the s3 backend's `endpoints.s3`. It is present on all targets (init, plan/apply/
   refresh/destroy) because the backend needs it to reach R2 each run. No template, no
   render script, no generated file, and NO `unset` around the endpoint var.
3. `infra/aws/provider.tf` pins `endpoints { s3 = "https://s3.<region>.amazonaws.com" }` —
   this pin is the **sole** thing that keeps real `aws_s3_bucket` / `aws_s3_bucket_policy`
   calls resolving to AWS while the R2 endpoint var is present.
4. Non-AWS modules (`cloudflare`, `doks`, `k3s`) carry the same inline backend block and
   need no provider pin (no AWS provider); they just run with the endpoint var present.
5. R2 creds stay under `TF_VAR_R2_*` and real AWS creds under `AWS_ACCESS_KEY_ID`/
   `AWS_SECRET_ACCESS_KEY`; never move R2 creds to a bare `AWS_*` name.

### Old (per-module template) vs new (flat ambient + pin)

| Step | Per-module `.tfbackend` | Flat ambient + pin (now) |
| --- | --- | --- |
| Endpoint delivery | committed `*.tpl` rendered at `init` | ambient `AWS_ENDPOINT_URL_S3` on all runs |
| Structural backend home | per-module template + stubbed `versions.tf` | inline `versions.tf` `backend "s3"` block |
| Render step / script | yes (`scripts/render-tfbackend.sh`) | none |
| AWS provider S3 routing | defaults to real AWS (no var in env) | pinned via `endpoints.s3` in `provider.tf` |
| Endpoint var at mutate time | absent (durable cached binding) | present (backend needs it); pin protects |

## Consequences

### Positive
- **Less indirection:** no template files, no render script, no generated-backend path
  plumbing, no gitignore of `*.tfbackend.generated`. One ambient env var, one provider
  pin, and one Makefile flag block.
- Structural backend config lives in the canonical `versions.tf` `backend` block again.
- Live-verified on the only populated module (`k3s`): `make plan MOD=k3s` returns **No
  changes** with the flat ambient-endpoint + inline-block config.

### Negative / trade-offs
- Reintroduces a **shared ambient `AWS_ENDPOINT_URL_S3`** knob that both the backend and the
  AWS provider read. Safety for the `aws` module now rests entirely on its `endpoints.s3`
  pin, not on the var being absent. This is the known residual that pushed the earlier
  design toward the per-module template; it is accepted as a controlled, documented
  trade-off for a personal sandbox.
- A first-cut `unset` guard was attempted and reverted after it broke the backend (the
  endpoint var is needed each run); the failing invocation is the record of why.

### Risks
- If a future editor removes or weakens the `endpoints.s3` pin in `infra/aws/provider.tf`
  while `AWS_ENDPOINT_URL_S3` is set, the `aws` provider regresses to R2-routing
  (`access key has length 20, should be 32`). Keep the pin; treat the endpoint var's
  presence as the default for all runs.
- Do **not** `unset AWS_ENDPOINT_URL_S3` around plan/apply/refresh/destroy — that starves
  the backend's own R2 connection.
- If the endpoint/credential split ever gets more complex (multi-operator, an account
  where R2 and AWS genuinely collide again), the documented, correct escalation is
  separating backend+provider into distinct processes, not restoring the per-module
  template layer or adding an env `unset`.

## Alternatives considered (and rejected)

1. **Keep the per-module `.tfbackend`/render layer.** Rejected as over-engineered for this
   repo's scale (this revision's whole point).
2. **Split backend and provider into separate Terraform configurations.** Cleanest in
   principle, but a much larger architectural change than a single-owner module-per-dir
   repo needs.

## Migration / correctness notes (for future agents)

- Reproduce a fresh bind: `make reconfigure MOD=<m>`, then `make plan MOD=<m>` should be
  **No changes** on configured modules. Backend reads `AWS_ENDPOINT_URL_S3` from Infisical
  (present on all runs), so the R2 account id lives in that single env var. The `aws`
  provider must keep its `endpoints.s3` pin; non-AWS modules need none.
- Do **not** introduce an `unset AWS_ENDPOINT_URL_*` guard around plan/apply/refresh/
  destroy: the endpoint var is required every run for the backend to reach R2 (see why
  in **Consequences / Negative**). Rely on the `provider.tf` pin for the `aws` provider.
- See `docs/incident-2026-08-27-r2-backend-credential-conflict.md` for the original
  collision and why the namespace split exists.
