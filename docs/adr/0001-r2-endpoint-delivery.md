# ADR 0001: R2 state-backend endpoint delivery

- **Status:** Accepted (2026-11-19 revision: the endpoint is a backend flag at init, not an environment variable)
- **Date:** 2026-11-19 (first accepted 2026-09-07)
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
| 2026-09-08 | Ambient `AWS_ENDPOINT_URL_S3` present on all runs + `endpoints.s3` pin in `provider.tf`. | **Superseded** on 2026-11-19 |
| **2026-11-19** | **Current:** `TF_VAR_R2_ENDPOINT` passed as `endpoints.s3` in the init flags, stored with the rest of the backend config. No `AWS_*` endpoint var on any target. | **Accepted** |

**2026-11-19 revision note:** the 2026-09-08 design rested on two claims. The first, that the
endpoint must be in the environment on every run, was a stale-binding artifact: a live test on
Terraform 1.16.5 shows `-backend-config=endpoints={s3="..."}` is stored in
`.terraform/terraform.tfstate` alongside the creds and reused by `plan` with no endpoint in the
environment. The second, that the address had to come from an ambient var at all, was the
thing the reverted template solved correctly; it needed a flag, not a template. Delivering it
as one more init flag keeps the split and drops both the template layer and the shared var.

**Why the per-module iteration was reverted (2026-09-08):** it was over-engineered for a
single-owner sandbox — one committed template + a render script + `TFBACKEND_OUT(_REL)`
Makefile plumbing per module just to deliver one non-secret endpoint URL (YAGNI). It also
moved structural backend config out of the canonical `versions.tf` `backend "s3"` block into a
parallel template, splitting configuration across two sources of truth. The real incident fix
was never the template — it is cred namespacing (`TF_VAR_R2_*`) plus, in the flat design, the
`provider.tf` `endpoints.s3` pin; the `unset` guard that broke `make plan MOD=k3s` at the time
was read as proof the env var was required, which the 2026-11-19 revision supersedes.

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
`TF_VAR_R2_*`** so they cannot shadow the AWS provider creds. The 2026-09-08 revision read a
failed `make plan MOD=k3s` (with the endpoint var unset) as proof that the endpoint had to be
in the environment on every run. It was a stale binding: the plan ran before the address was
stored in that module's backend config, so it fell back to `*.s3.auto.amazonaws.com`. The
2026-11-19 revision stores the address at init, which removes the need for the var entirely.

## Decision

**Deliver the R2 endpoint as `TF_VAR_R2_ENDPOINT` on the init flags (`endpoints.s3`), keep
structural backend settings inline in each `versions.tf`, and pin the AWS provider to real
S3.** Nothing re-reads an endpoint from the environment after init, so the pin is a guard
against a variable coming back, not the primary defence.

Terraform opens the state client and the provider in one process for `plan` and `apply`, and
`init` touches only the state side. That is why the address is delivered at init and nowhere
else. No command splits the two, so no arrangement of environments, workspaces or root
modules separates them either.

1. Each module's `versions.tf` keeps a real inline `backend "s3"` block carrying
   `bucket`, `key`, `region`, `skip_*` and `use_lockfile`. Only the two secret creds and
   `endpoints.s3` are supplied as `-backend-config` flags in the Makefile (init-style
   targets run through `/bin/sh -c` so the `$TF_VAR_R2_*` refs expand from infisical's
   injected env), because they cannot live in a committed file.
2. The R2 endpoint is `TF_VAR_R2_ENDPOINT`, passed at init as
   `-backend-config="endpoints={s3=...}"`. Init stores it in
   `.terraform/terraform.tfstate`, so plan/apply/refresh/destroy read it from the working
   directory and never from the environment. No template, no render script, no generated
   file, and no `AWS_*` endpoint var on any target.
3. `infra/aws/provider.tf` pins `endpoints { s3 = "https://s3.<region>.amazonaws.com" }` —
   this pin is what keeps real `aws_s3_bucket` / `aws_s3_bucket_policy` calls resolving to
   AWS if an endpoint setting ever reappears in the environment.
4. Non-AWS modules (`cloudflare`, `k3s`) carry the same inline backend block and
   need no provider pin (no AWS provider); they need nothing extra either.
5. R2 creds stay under `TF_VAR_R2_*` and real AWS creds under `AWS_ACCESS_KEY_ID`/
   `AWS_SECRET_ACCESS_KEY`; never move R2 creds to a bare `AWS_*` name.

### Old (per-module template) vs 2026-09-08 design (superseded)

| Step | Per-module `.tfbackend` | Flat ambient + pin (2026-09-08, superseded) |
| --- | --- | --- |
| Endpoint delivery | committed `*.tpl` rendered at `init` | ambient `AWS_ENDPOINT_URL_S3` on all runs |
| Structural backend home | per-module template + stubbed `versions.tf` | inline `versions.tf` `backend "s3"` block |
| Render step / script | yes (`scripts/render-tfbackend.sh`) | none |
| AWS provider S3 routing | defaults to real AWS (no var in env) | pinned via `endpoints.s3` in `provider.tf` |
| Endpoint var at mutate time | absent (durable cached binding) | present (backend needs it); pin protects |

## Consequences

### Positive
- **Less indirection:** no template files, no render script, no generated-backend path
  plumbing, no gitignore of `*.tfbackend.generated`. One provider pin and one Makefile flag
  block, and no endpoint variable in the environment at all.
- The `aws` provider cannot inherit the R2 address, because nothing hands it one.
- Structural backend config lives in the canonical `versions.tf` `backend` block again.

### Negative / trade-offs
- The 2026-09-08 revision accepted a shared ambient `AWS_ENDPOINT_URL_S3` knob and left
  safety resting on the pin. That residual is gone: the address is stored per module and no
  process environment carries it.
- A first-cut `unset` guard was attempted during the 2026-09-08 revision and reverted after
  it broke the backend; that failure is explained by the binding not yet having the address
  stored (see the revision note above), not by the env var being required.

### Risks
- If a future editor removes or weakens the `endpoints.s3` pin in `infra/aws/provider.tf`
  while `AWS_ENDPOINT_URL_S3` is set, the `aws` provider regresses to R2-routing
  (`access key has length 20, should be 32`). Keep the pin as the guard against that var
  coming back.
- If the endpoint/credential split ever gets more complex (multi-operator, an account
  where R2 and AWS genuinely collide again), separating the two into distinct processes is
  not available: a single plan opens both in one process. The escalation is moving state to
  a backend that does not use the AWS SDK at all (`remote`, `pg`, `consul`), which removes
  the shared namespace instead of arbitrating it.

## Alternatives considered (and rejected)

1. **Keep the per-module `.tfbackend`/render layer.** Rejected as over-engineered for this
   repo's scale (this revision's whole point).
2. **Split backend and provider into separate Terraform configurations.** Does not change
   anything: each configuration still opens its own state client and provider in one
   process, so the shared `AWS_*` namespace comes along. The variant that does work is a
   state backend outside the AWS SDK, at the cost of a vendor or a database. Too large for
   a single-owner module-per-dir repo.

## Migration / correctness notes (for future agents)

- Reproduce a fresh bind: `make reconfigure MOD=<m>`, then `make plan MOD=<m>`. The bind is
  correct if the plan reaches R2 and reports the same changes it reported before the rebind;
  a backend or credential error means the bind is wrong. The address comes from
  `TF_VAR_R2_ENDPOINT` at init only, and is stored from then on. The `aws` provider must keep
  its `endpoints.s3` pin; non-AWS modules need none.
- Changing the R2 endpoint means another `make reconfigure MOD=<m>`: nothing re-reads the
  environment afterwards.
- Leave `AWS_ENDPOINT_URL_S3`, `AWS_ENDPOINT_URL`, and `AWS_S3_ENDPOINT` unset in the
  Infisical project. They are only read if init falls back to them, which the rename removes.
- See `docs/incident-2026-08-27-r2-backend-credential-conflict.md` for the original
  collision and why the namespace split exists.
