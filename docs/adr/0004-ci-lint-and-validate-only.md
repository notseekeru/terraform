# ADR 0004 — CI is `fmt` + `validate` only (no plan, no apply in CI)

- **Status:** Accepted
- **Date:** 2026-09-25
- **Related:** ADR 0001, ADR 0002 (partially amended), `Makefile`, `.github/workflows/ci.yml`

---

## Context

ADR 0002 rejected a CI/CD pipeline outright. That was correct about `apply` and wrong in one
detail: `terraform fmt` and `terraform validate` need **no credentials at all**, so they can run on
every push without touching the surfaces ADR 0001 removed. `validate` catches exactly the failure
class that is otherwise caught by a person reading a diff: syntax, type and reference errors, bad
variable/attribute names, malformed HCL, provider schema drift.

The expensive half is `plan`. A real plan needs the R2 backend (state) plus every `TF_VAR_*` and
every provider token for that module, i.e. the whole Infisical `/consumers/terraform` consumer
mirrored into a CI secret store, under a machine identity. A plan without those credentials is not
a cheaper plan, it is a *wrong* plan: it diffs against empty state and its output cannot be trusted
as a gate.

The operational cost is not only the secret set:

- **It holds the state lock.** A read-only `plan` still locks the module through refresh and plan. An
  every-push CI plan would contend with the operator's `apply` on a per-module lock, and a runner
  killed mid-plan leaves a stale lock that only `terraform force-unlock` clears. Automating a lock
  breaker is how state gets corrupted.
- **Approval is stale by construction.** A CI plan describes state at CI time; the apply happens later,
  locally, against whatever state exists then. Unless CI applies the exact artifact that was approved,
  the approval certifies a diff nobody runs.
- **Nobody consumes it.** Single owner, no PR gate, so a plan comment has no reviewer to act on it.

## Decision

CI runs on push and PR: `terraform fmt -check -recursive infra` once, then per module
(`aws`, `cloudflare`, `k3s`) `terraform init -backend=false` and `terraform validate`. Nothing else.

Explicitly out of scope in CI:

- **`apply`.** Stays human-gated via `make apply MOD=…` (ADR 0002 unchanged).
- **`plan`.** Stays local via `make plan MOD=…`, where Infisical supplies real values and the R2
  backend supplies real state.
- **Any secret, any provider credential, any ambient cloud identity.** The workflow is credential-free,
  which is also why it is safe to run on forked PRs.
- **Lock-file enforcement.** `.terraform.lock.hcl` stays gitignored; CI resolves providers fresh, so a
  constraint bump is exercised rather than silently validated against an old lock.

Escalate only on a concrete trigger (same triggers as ADR 0002): a second applier, non-interactive
deploys, or a required audit trail. Adding a `plan` job means first solving credential scoping
(read-only, per-module, short-lived), and it should be a new ADR.

## Consequences

### Positive

- Feedback in about a minute, free, on every push, with no secrets to rotate or leak.
- Typo-class errors stop reaching `make plan`, where they cost a full backend connect and provider
  init to surface instead of a red check.
- The credential surface stays exactly as ADR 0001 left it.
- `AI HERE:` if flake.lock bumps Terraform, bump `terraform_version` in the workflow to match; the two
  are not linked automatically. Ceiling: pin drift shows up as a CI-only fmt/validate difference.

### Negative / trade-offs

- `validate` proves nothing about reality: not permissions, quotas, name collisions, existing
  resources, or the R2 backend config (skipped by `-backend=false`). It is a syntax gate, not a
  safety gate, and must not be read as approval to skip `make plan`.
- CI cannot catch provider-side breakage (`fmt`/`validate` pass on a config that will 403 on apply).
- A fresh provider download per job: slower than a cached lock, and it will not notice a resolution
  that differs from the operator's local `.terraform`.
- Two places now run Terraform (CI for checks, operator for state), so "it passed CI" is not evidence
  about state, only about HCL.

### Risks

- Green CI mistaken for a reviewed change. Mitigated by the mandatory `make plan` review before
  `apply`, which remains the only gate that sees real state.

---

## Alternatives considered

1. **No CI at all (ADR 0002 as written).** Rejected: the credential-free subset is free and its absence
   only buys the operator a slower feedback loop.
2. **CI with a credentialed `plan` job.** Rejected for now: requires the full secret set plus a machine
   identity for R2 state, re-adding an automation credential to reason about. It would also hold the
   per-module state lock for every run, and its approval would be stale by the time the operator
   applies. Reconsider only on an ADR 0002 trigger, with read-only scoped credentials.
3. **CI `plan` with `-backend=false`.** Rejected: plans against empty state and reports a full create
   of everything, which is worse than no output.
4. **Pre-commit hook instead of CI.** Rejected: checks only the committing machine, bypassable with
   `--no-verify`, and invisible in PRs.
