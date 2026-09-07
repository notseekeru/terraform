# ADR 0002 — No CI/CD for the infrastructure pipeline (human-gated applies)

- **Status:** Accepted (single-owner sandbox)
- **Date:** 2026-09-07 (decision predates; formalized here)
- **Related:** ADR 0001, `Makefile`, `README.md` §Locking, R2 S3-native locking

---

## Context

Terraform state and resources are managed from a lone operator's machine via `make`
targets. State lives in Cloudflare R2 with **S3-native `use_lockfile` locking** per module
(ADR 0001 / README §Locking), which already prevents two concurrent applies of the same
module from corrupting state. A full plan→approve→apply CI/CD pipeline is possible but
expensive (and, per ADR 0001, an extra credential/endpoint surface).

Key facts:

- **Single owner.** Only one human can run `apply`.
- **Applies are already human-gated.** `make apply MOD=<m>` prompts (no auto-approve),
  and the workflow requires a human-reviewed `plan` before `apply`.
- **Locking already handles the concurrency risk.** Two applies of the *same* module
  serialize via the R2 lockfile; different modules run fine in parallel.
- Secrets live in Infisical and are injected by `infisical run`; no CI secret store exists.

## Decision

**Do not add a CI/CD pipeline for infrastructure right now.** Keep deploys as manual,
human-gated `make plan` / `make apply` runs by the single owner. A pipeline is deliberately
**absent**, not an oversight.

Re-introduce orchestration only when a concrete trigger appears:

- a **second person or a machine** needs `apply` access (need one authorized path + audit
  trail), or
- **non-interactive, reviewed deploys** are required.

When that happens, the cheap escalation ladder, in order:

1. **Single centralized apply path** — one shared runner/entrypoint authorized to `apply`
   (not per-developer `apply` access).
2. **Atlantis / Spacelift / Terraform Cloud** — only when you also want PR-driven
   plan/apply, policy (OPA/sentinel), or per-user audit.

## Consequences

### Positive
- No runner to maintain, no CI credential surface, no deploy latency.
- The R2 `use_lockfile` guard suffices for the actual concurrency risk (same-module
  applies serialize).
- Every change is intentional and reviewed by a human (`plan` before `apply`), which is
  the strongest practical safety for a single-owner repo.
- Avoids the ambient-credential surface area that ADR 0001 specifically set out to remove;
  a CI system would reintroduce a machine credential pipeline to reason about.

### Negative / trade-offs
- No audit trail of *who* applied *what* (relies on git history + human memory).
- No non-interactive/repeatable deploys; a fresh clone needs an operator present
  (see README §Fresh clone).
- No PR-gated plan/apply or automated policy checks.
- If a second contributor or automation is ever added, `apply` entitlement must be
  reconsidered (see escalation ladder above) rather than assumed safe.

### Risks
- A misapplied manual change has no pipeline gate; mitigated by the mandatory
  `make plan` review + prompts.
- Locking only serializes Terraform on the **same** module; it does not stop out-of-band
  destructive changes (`make nuke-list`, console edits, `aws-nuke`) — see README §Locking
  operating rules.

---

## Alternatives considered

1. **Full Atlantis/Spacelift/Terraform Cloud now.** Rejected: over-provisioned for a
   single owner; adds runner, CI credential surface (opposing ADR 0001), and latency with
   no extra safety today.
2. **A minimal apply-only CI job (single runner, no PR gating).** The acceptable *future*
   step per the escalation ladder, but not needed while one human owns `apply`.
3. **Per-developer apply access.** Rejected: scatters the destructive authority and audit
   responsibility; a single authorized path is strictly better when a team is needed.

---

## Deciding triggers (checklist for future agents)

Before proposing a pipeline, confirm at least one is true:
- [ ] A second person will run `apply`.
- [ ] A machine/automation will run `apply` non-interactively.
- [ ] An audit of *who applied what* is required.
- [ ] Deploys must be repeatable without an operator.

If none apply, keep manual `make plan` / `make apply`. If one does, escalate per the ladder
in §Decision and record it as a new ADR superseding this one.
