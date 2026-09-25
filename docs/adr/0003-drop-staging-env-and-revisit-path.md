# ADR 0003 — Drop the staging environment (and the exact path to rebuild it)

- **Status:** Accepted
- **Date:** 2026-09-19
- **Related:** ADR 0002, PLAN D11/D13/D14 (maxterview_website), `gitops` README, `.github/workflows/cd-pipeline.yml`

---

## Context

Staging was a full second environment: its own Neon project, Infisical `staging` environment, Terraform
root module + R2 state, k8s namespace + secrets, ArgoCD Application, DNS hostname, and a second frontend
image build (the SPA inlines its Clerk publishable key at build time, so a different Clerk instance needs a
different image). It existed to rehearse migrations and to host load tests — **not** as a release gate:
ADR-adjacent decision D13 ships every green `main` straight to prod, so nothing was ever promoted from
staging.

Costs it actually carried: ~4 extra files in this repo, a second env of ~30 secrets to keep mirrored,
a duplicate SQLAlchemy/Neon quota consumer, two namespaces' worth of concept load, and a `MOD` typo class
that needed cross-refusing endpoint guards on both sides.

Two things made it pointless: **no users** (nothing to protect from a bad deploy) and a **one-man team**
(nobody else needs a rehearsal target to review against).

## Decision

**Drop staging.** One durable environment (prod) + local dev/CI Postgres. Reintroduce it only via the
path below, and only when a real trigger exists:

- a second person needs a shared non-prod target, or
- a migration/load test can no longer be rehearsed safely enough on a disposable Neon branch, or
- a contract/customer requires a non-prod environment to exist.

## What was removed (2026-09-19)

| Layer     | Removed                                                                                                                                                                                                                   |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Neon      | project `maxterview-staging` (own project, per D11)                                                                                                                                                                       |
| Infisical | environment `staging`, folder `/consumers/terraform` (~24 `${prod...}` refs + 5 local overrides)                                                                                                                          |
| Terraform | `infra/k3s-staging/` root module + state key `terraform/k3s-staging/terraform.tfstate`; the staging-endpoint refusal guard in `infra/k3s/variables.tf`; the `maxterview_staging` CNAME in `infra/cloudflare/variables.tf` |
| K8s       | namespace `maxterview-staging`, `maxterview-staging-secrets`, its namespace-local `ghcr-login`                                                                                                                            |
| GitOps    | `apps-of-apps/maxterview-staging.yaml`, `apps/maxterview/overlays/staging/`                                                                                                                                               |
| App repo  | CD matrix entry `frontend-staging` (`staging-<sha>` tag), the second overlay bump in `update-gitops-repo`, `frontend/.env.staging`, Dockerfile `ARG VITE_MODE`                                                            |

An empty `terraform/k3s-staging/terraform.tfstate` may survive in R2 — harmless, and re-bindable if staging
comes back (`make init MOD=k3s-staging` overwrites nothing, it reads).

## How to rebuild it

Order matters: database and secrets first, then the cluster objects, then GitOps (Argo syncs on push), then
the image build.

1. **Neon** — new project in `aws-ap-southeast-1`. Take the **direct** host DSN (not `-pooler`) with
   `?sslmode=require`. Per D11 it must be its own project: free-plan quota is per project, so a busy staging
   cannot starve prod's compute. Branches (PR/preview, migration rehearsal) belong to the staging project,
   never prod's.
2. **Infisical** — create environment `staging`, folder `/consumers/terraform` **in that env first**
   (a missing folder 404s the write pre-check), then mirror prod's key set as **per-key references** in dot
   form: `TF_VAR_R2_BUCKET=${prod.consumers.terraform.TF_VAR_R2_BUCKET}`. The dashboard's env-inheritance
   toggle does not reach the API/CLI, and `${prod./a/b.KEY}` (slash form) stores verbatim. Mirror the full set
   — later additions to prod do **not** propagate. Local overrides, never references: `DATABASE_URL` (staging
   DSN), `CLERK_DOMAIN`/`CLERK_JWKS_URL` (the Clerk **Development** instance, not `clerk.seekeru.tech`),
   `PAYMONGO_SECRET_KEY`/`_WEBHOOK_SECRET` (the `sk_test_`/`whsk_` pair — prod's are live). Use the profile
   Infisical CLI (0.43.x);
3. **Terraform** — re-add `infra/k3s-staging/` as its own root module + state key (`MOD` builds the key, so it
   stays isolated from `infra/k3s`). Three objects: namespace `maxterview-staging`,
   `maxterview-staging-secrets` (11 UPPERCASE env-var keys, `envFrom` is all-or-nothing), and the
   namespace-local `ghcr-login` (`imagePullSecrets` never cross namespaces and the GHCR packages are private,
   so without it every pod — including the PreSync migrate Job, which then aborts the sync — sits in
   ImagePullBackOff). Restore both plan-time guards: staging refuses prod's Neon endpoint, `infra/k3s` refuses
   staging's, so a `MOD`/`ENV` typo cannot point one env at the other's database. Apply DNS in
   `infra/cloudflare/variables.tf` as a **first-level** hostname (`maxterview-staging.seekeru.tech`):
   Universal SSL covers `<zone>` + `*.<zone>` only.
4. **GitOps** — re-add `apps-of-apps/maxterview-staging.yaml` (child Application, `prune` + `selfHeal`,
   destination namespace `maxterview-staging`) and `apps/maxterview/overlays/staging/`: the base stays
   env-neutral, the overlay patches namespace, ingress host, `APP_ENV=staging`, `FRONTEND_BASE_URL`, the two
   `secretRef` names, and pins the `staging-` frontend tag.
5. **App repo** — re-add `frontend/.env.staging` with the Development instance's `pk_test_` (a `pk_` is
   `pk_<mode>_` + base64 of the Frontend API host; safe to commit, Vite inlines it into `dist/assets/*.js`),
   restore `ARG VITE_MODE` in the frontend Dockerfile, and re-add the CD matrix entry (`tag_prefix: staging-`,
   `latest: "false"` — an unqualified pull must stay the prod SPA) plus its overlay bump. This second image
   exists only because the Clerk instance is baked at build time; runtime injection via an nginx `config.js`
   is the documented alternative (9 files across 3 repos) if a third env ever appears.

## Consequences

- **Positive:** one environment to keep true; no mirrored secret set to drift; no duplicate Neon quota
  consumer; no `MOD`-typo guard class; one image per service; less machinery to explain.
- **Negative, accepted:** no migration rehearsal target — a bad migration is first exercised in prod, so
  rehearse on a disposable Neon branch of the **prod** project (never its default branch, and drop it after);
  no safe load-test target — measure against prod in a low-traffic window with the generator off-node and
  `LLM_BASE_URL` empty (STUB_MODE), accepting the availability risk on `replicas: 1`.
- **Reversal cost:** roughly a day, and the rebuild path above is the checklist. Record the reversal as a new
  ADR superseding this one.
