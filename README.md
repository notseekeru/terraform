# Terraform — Personal Cloud Infrastructure

> Infrastructure-as-Code for my personal cloud environment.
> **Providers:** DigitalOcean / Cloudflare (R2 + DNS) / AWS · **Provisioner:** Terraform · **Orchestrator:** ArgoCD
> **AI usage is encouraged** — ask an agent to explain, audit, or change infra. Every change still ends with a human-reviewed `plan`; AI is a helper, not a dependency.

---

## Prerequisites

| Requirement            | Details                                                                                 |
| ---------------------- | --------------------------------------------------------------------------------------- |
| **Terraform**          | `>= 1.0` ([install](https://developer.hashicorp.com/terraform/install))                 |
| **DigitalOcean Token** | Fine-grained PAT with write scope (`DO_TOKEN`) — only for `doks`                        |
| **Cloudflare token**   | API token `Zone → DNS → Edit` (`TF_VAR_CLOUDFLARE_API_TOKEN`) — for `cloudflare` module |
| **k3s**                | Existing k3s cluster with `~/.kube/config` — see [K3s Module](#k3s-module-local)        |
| **Nix / direnv**       | Optional: `nix develop` shell; `direnv` auto-loads it, pulls, exports `KUBECONFIG`      |

`make` is optional (workflow targets). Secrets are not shipped in the repo — see [Fresh clone](#fresh-clone-on-a-new-device).

---

## Remote state (R2) & locking

State lives in a **Cloudflare R2 bucket** (`s3` backend) under a per-module key — no committed local state.

| Module       | State key                                | Backend |
| ------------ | ---------------------------------------- | ------- |
| `doks`       | `terraform/doks/terraform.tfstate`       | s3      |
| `k3s`        | `terraform/k3s/terraform.tfstate`        | s3      |
| `aws`        | `terraform/aws/terraform.tfstate`        | s3      |
| `cloudflare` | `terraform/cloudflare/terraform.tfstate` | s3      |

**How the R2 endpoint is delivered (read once):** the s3 backend and the AWS provider both read the ambient `AWS_*` namespace, so they must be kept from colliding:

- R2 creds stay namespaced `TF_VAR_R2_*` (`TF_VAR_R2_BUCKET`, `..._ACCESS_KEY_ID`, `..._SECRET_ACCESS_KEY`); AWS creds stay `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`. Never use a bare `AWS_*` name for R2 creds.
- The **R2 endpoint** is the ambient `AWS_ENDPOINT_URL_S3`, present on **every** run because the s3 backend needs it to reach R2 (init **and** plan/apply/refresh/destroy). Same var on a fresh box: set it to `https://<account>.r2.cloudflarestorage.com`.
- Because that var is also read by the AWS provider, `infra/aws/provider.tf` pins `endpoints { s3 = "https://s3.ap-southeast-1.amazonaws.com" }`. That pin — not an env `unset` — keeps real `aws_s3_bucket*` calls in AWS.

> **Do not** `unset AWS_ENDPOINT_URL_S3` around plan/apply/refresh/destroy — that starves the backend's own R2 connection. Removing or weakening the `aws` provider pin routes AWS bucket calls to R2 (`access key has length 20, should be 32`). Full rationale + history: **ADR 0001** (`docs/adr/0001-r2-endpoint-ambient-env-provider-pin.md`).

Backend settings live inline in each module's `versions.tf` `backend "s3"` block. Static fields (`skip_*`, `use_lockfile`, region) are inline; `bucket`/`key` and the two R2 creds come from `-backend-config` flags in the Makefile (init targets run via `/bin/sh -c` so `$TF_VAR_R2_*` expands). After `init`, the binding caches in `infra/<MOD>/.terraform/`. First-time push of pre-existing local state: `make migrate MOD=<m>`.

### Operating rules

When no CI stage runs and only `make apply` gates concurrency, follow these:

- One `apply`/`destroy` per module at a time. Different modules can run in parallel (state keys differ; locks are per-module).
- Run with `-lock-timeout=30s` so a contended/stale lock fails fast instead of hanging.
- A read-only `plan` also holds the state lock through refresh+plan; two parallel `plan`s serialize.
- `use_lockfile = true` guards **same-module** Terraform runs only — it does not stop out-of-band destructive changes (`aws-nuke`, console edits). Tests on the shared bucket verified the S3-native lock (`412 PreconditionFailed`); re-test if the backend ever moves off R2.
- Stale lock after a crash: run `terraform force-unlock <LOCK_ID>` (the ID is in the error) once you're sure no apply is live. `-lock=false` is an emergency bypass only.

## No CI/CD is deliberate

Single-owner sandbox: applies are human-gated via `make apply` (reviewed `plan` first) and the R2 lock serializes same-module runs. A plan→approve→apply pipeline now would add a runner and a CI credential surface for zero extra safety. Add orchestration only if a second person/machine needs `apply`, or you need non-interactive reviewed deploys. Full rationale, trade-offs, and the escalation ladder: **ADR 0002** (`docs/adr/0002-no-cicd-manual-human-gated-applies.md`).

---

## Quickstart

```bash
cd terraform

# Secrets come from Infisical (direnv/.envrc wires the shell; there is no secrets.tfvars flow).
#   -- If you use k3s, install k3s first.
make init MOD=k3s    # init providers + bind R2 backend
make plan MOD=k3s    # preview
make apply MOD=k3s   # apply
```

### Fresh clone on a new device

The repo is operator-reproducible, not fresh-clone-self-contained. Before init/plan works on a new machine (none of this ships in the repo, by design):

1. **Infisical identity** — copy `~/.config/infisical/` from a working device (or `infisical login`) plus this workspace's `.infisical.json` (`/terraform` dev).
2. **Secrets populated** — the Infisical project must hold the `TF_VAR_*`/`AWS_*` vars each module's `variables.tf` needs, incl. the R2 set (`TF_VAR_R2_*`) and ambient `AWS_ENDPOINT_URL_S3`.
3. **R2 state bucket live** — creds must still point at the existing `terraform-state` bucket.
4. **`gitops/` repo checked out at `../gitops/`** — `doks`/`k3s` read `app.yaml` via `file()` at apply time.
5. **ArgoCD/GHCR reachable** — the PAT in Infisical must still be valid for the private `gitops` repo.

Then `make init MOD=<m>` re-fetches providers. `.terraform.lock.hcl` and local `*.tfstate` are gitignored, so first init on a machine re-resolves against `~>` floors (a minor drift vector).

---

## Project Layout

```
terraform/
├── infra/                   # Terraform root modules
│   ├── doks/                #   state #1 — DOKS cluster (cloud)
│   ├── k3s/                 #   state #2 — local k3s cluster (no DO)
│   ├── aws/                 #   state #3 — AWS sandbox (see AWS.md)
│   └── cloudflare/          #   state #4 — Cloudflare DNS + zone settings
├── Makefile                 # Workflow targets (accepts MOD=, ENV=, SECRETS_PATH=)
├── flake.nix                # Nix dev shell definition
├── .envrc                   # direnv: auto-nix + git pull + KUBECONFIG
├── secrets.tfvars.example   # Dummy/empty template for reference only (gitignored live file: secrets.tfvars)
└── docs/                    # ADRs + incident runbooks
```

Each module keeps its own `versions.tf`, `provider.tf`, `variables.tf`, `main.tf`, and split resource files (e.g. `infra/aws/{vpc,compute,storage,database,security,monitoring,secrets,outputs}.tf`). `infra/cloudflare/README.md` is the import-first adoption runbook. Full architecture: `AWS.md`.

---

## Makefile Workflow

Module targets take `MOD=doks|k3s|aws|cloudflare`; the `infra/` prefix and Infisical flow are baked in. Backend-facing targets (`init`, `upgradeinit`, `reconfigure`, `migrate`) pass `backend_config` through `/bin/sh -c` so the `$TF_VAR_R2_*` refs expand (Infisical execs directly and wouldn't expand them). The R2 endpoint is the ambient `AWS_ENDPOINT_URL_S3` present on all targets. Backend/`aws`-provider separation is handled by the provider pin — not an env `unset`. `nuke-list` is account-scoped (ignores `MOD`) and runs from the repo root.

| Target             | Description                                                |
| ------------------ | ---------------------------------------------------------- |
| `make init`        | Init providers + bind R2 backend                           |
| `make upgradeinit` | Upgrade providers / re-bind backend (`-upgrade`)           |
| `make plan`        | Preview changes                                            |
| `make apply`       | Apply changes                                              |
| `make destroy`     | Tear down resources                                        |
| `make fmt`         | Format `.tf` files                                         |
| `make validate`    | Validate module                                            |
| `make migrate`     | One-time push of local state to R2 (`init -migrate-state`) |
| `make dump`        | Dump `diagramdb` from local k3s postgres → `~/backups/`    |
| `make nuke-list`   | **Dry-run** aws-nuke sweep — deletes nothing               |

**Variables:** `MOD` (slugs above), `ENV` (default `dev`), `SECRETS_PATH` (default `/terraform`).

```bash
make init MOD=k3s && make plan MOD=k3s && make apply MOD=k3s
make plan MOD=cloudflare && make apply MOD=cloudflare
make migrate MOD=k3s    # one-time local→R2 state copy
```

## DOKS Cluster (Cloud)

| Attribute     | Value                | Notes                   |
| ------------- | -------------------- | ----------------------- |
| **Name**      | `lab-cluster`        | Singleton — one cluster |
| **Region**    | `var.default_region` | Inherits `sgp1` default |
| **Version**   | `1.34.8-do.2`        | DO-managed K8s          |
| **Node pool** | 3 × `s-2vcpu-2gb`    | 6 GB total              |

kubeconfig is written to `~/kubeconfig` at apply time:

```bash
export KUBECONFIG=~/kubeconfig && kubectl get nodes
```

A DO managed PostgreSQL 16 (`db-s-1vcpu-1gb`) lives in the cluster VPC; creds go into `diagram-secrets` with `sslmode=no-verify` for private connectivity.

## K3s Module (Local)

For local/edge dev. Runs against an existing k3s cluster via `~/.kube/config`.

| Aspect                | Detail                                                                            |
| --------------------- | --------------------------------------------------------------------------------- |
| **No DO dependency**  | Providers read local kubeconfig                                                   |
| **Database**          | Self-hosted PG 16 StatefulSet, `database` ns, 5Gi PVC on `local-path`             |
| **Connection string** | `postgresql://diagram:${pass}@postgres.database.svc.cluster.local:5432/diagramdb` |

```bash
make init MOD=k3s && make plan MOD=k3s && make apply MOD=k3s
```

Needs Infisical secrets: `POSTGRES_PASSWORD`, `CLOUDFLARE_TOKEN`, `GITHUB_PAT`, `DIAGRAM_API_KEY`, plus the
maxterview set below. Back up the DB before `destroy`:

```bash
make dump   # → ~/backups/diagramdb-<timestamp>.sql.gz
```

### maxterview secrets (Neon — external DB, no in-cluster Postgres)

`kubernetes_secret.maxterview_secrets` is the one consumer-side contract for maxterview: the backend
Deployment injects it with `envFrom`, so **each key must literally equal the env var name** (UPPERCASE).

| Infisical key (path `/consumers/terraform`)                             | Required | Notes                                                    |
| ----------------------------------------------------------------------- | -------- | -------------------------------------------------------- |
| `TF_VAR_MAXTERVIEW_DATABASE_URL`                                        | yes      | Neon **direct** host + `?sslmode=require`, not `-pooler` |
| `TF_VAR_MAXTERVIEW_CLERK_JWKS_URL`                                      | yes      | prod instance JWKS (backend verifies JWTs)               |
| `TF_VAR_MAXTERVIEW_CLERK_DOMAIN`                                        | yes      | e.g. `https://clerk.seekeru.tech`                        |
| `TF_VAR_MAXTERVIEW_LLM_BASE_URL` / `_MODEL` / `_API_KEY`                | yes      | empty `LLM_*` = silent STUB mode, so these fail at plan  |
| `TF_VAR_MAXTERVIEW_STRIPE_SECRET_KEY` / `_WEBHOOK_SECRET` / `_PRICE_ID` | no       | unset → `/api/billing/*` answers 503                     |
| `TF_VAR_MAXTERVIEW_CLERK_AUDIENCE`                                      | no       | empty = accept tokens without an `aud` claim             |
| `TF_VAR_MAXTERVIEW_MIGRATE_DATABASE_URL`                                | no       | reserved (D12), migrate-role DSN for the migration Job   |

Extra keys added later are picked up with no manifest change (`envFrom`), but a _malformed_ key name is
all-or-nothing: it blocks the whole pod. Rotate from Infisical + `make apply MOD=k3s`; never `kubectl apply`
and never `secrets.tfvars`.

> `infra/doks/` has **no** equivalent secret yet — applying `MOD=doks` with maxterview in the GitOps repo
> would leave those pods in `CreateContainerConfigError` until a DO-side DB choice is made (Neon vs managed PG).

## AWS Module (Cloud)

`infra/aws/` (state #3) is an AWS sandbox: VPC + public subnets, an auto-scaling EC2 web tier behind an ALB, single-AZ RDS PostgreSQL, and a private S3 bucket served via CloudFront (OAC). State still lives in R2.

**Credentials** (Infisical): `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`, `TF_VAR_ALERT_EMAIL`, and the `TF_VAR_R2_*` backend pair.

Notable wiring:

- **ALB** (CPU target-tracking ASG) with ELB health checks; **S3+CloudFront** for static assets; **CloudWatch** CPU alarm + zero-spend/credit-cap budgets → SNS (`TF_VAR_ALERT_EMAIL`; confirm the subscription once).
- **HTTPS is optional & automatic** — set `ALB_DOMAIN` (here `alb.seekeru.tech`): the module's aliased `cloudflare` provider creates the `alb.*` CNAME + ACM validation CNAME, and `aws_acm_certificate_validation` waits until ISSUED before binding :443. No dashboard step. ALB records are deliberately kept in `infra/aws` (not `infra/cloudflare`) so each module is self-contained.
- **DB user:** `dbadmin` (PG reserves `admin`).

> Deployment notes, verified endpoints, the R2/AWS provider endpoint split, upgrade paths & revalidation: see **`AWS.md`**.

## Cloudflare Module (DNS)

`infra/cloudflare/` (state #4) makes tunnel-facing DNS declarative. Provider `cloudflare ~> 5.0`; state in R2.

**Scope** — the 4 tunnel hostnames on `seekeru.tech` (managed declaratively):

| Record                   | Type  | Target                       | Proxied |
| ------------------------ | ----- | ---------------------------- | ------- |
| `seekeru.tech` (apex)    | CNAME | `7bbbb5d4-…cfargotunnel.com` | yes     |
| `portfolio.seekeru.tech` | CNAME | `7bbbb5d4-…cfargotunnel.com` | yes     |
| `diagram.seekeru.tech`   | CNAME | `7bbbb5d4-…cfargotunnel.com` | yes     |
| `max.seekeru.tech`       | CNAME | `7bbbb5d4-…cfargotunnel.com` | yes     |

Imported into state first (adopt, don't overwrite), now tracked by Terraform.

**Left in the dashboard / owned elsewhere:** Clerk SaaS records (`accounts`, `clerk`, `clk._domainkey`, `clkmail`…), and the AWS ALB `alb.seekeru.tech` + ACM validation CNAME (owned by `infra/aws`), and any future statically-addressed record.

**Workflow** — edit the `records` map in `infra/cloudflare/variables.tf`, then plan/apply. To adopt a dashboard-created record, import it before config lands or apply will duplicate it — see `infra/cloudflare/README.md` for the full runbook + `terraform import`.

## ArgoCD

Installed via `argoproj/argo-helm` (chart `7.7.0`) in the `argocd` namespace with K8s secrets and a root Application CR.

**Bootstrap:** Terraform applies Helm charts + secrets → applies the root Application via the `kubectl` provider (the **only** direct manifest) → that root App syncs the rest from the GitOps repo. Manifest defaults to `${path.module}/../../../gitops/app.yaml` (resolved at plan time); override via `app_yaml_path` (`infra/{k3s,doks}/variables.tf`).

**CLI setup:**

```bash
PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d) \
  && kubectl port-forward svc/argocd-server -n argocd --address 0.0.0.0 8080:443
# Login: https://localhost:8080 — admin / $PASS
```

## Databases

DO **managed PG** for `doks`; **self-hosted StatefulSet** for `k3s` (see per-module sections). Connection string + API key are injected into the `diagram-secrets` K8s secret consumed by app pods.

**Rotation / incident runbooks:**

- `docs/incident-2026-09-03-postgres-credential-mismatch.md` — a manual `ALTER USER` split the role password from `diagram-secrets` and broke backend auth over TCP (no data loss); includes the safe rotate-via-Terraform procedure.
- `docs/incident-2026-08-27-r2-backend-credential-conflict.md` — the R2/real-AWS credential collision behind the `TF_VAR_R2_*` namespace split.

## K8s Secrets (created by Terraform)

| Secret Name            | Namespace  | Purpose                                                 |
| ---------------------- | ---------- | ------------------------------------------------------- |
| `cloudflared-token`    | `default`  | Cloudflare Tunnel token for `cloudflared`               |
| `ghcr-login`           | `default`  | Docker registry creds for GHCR                          |
| `diagram-secrets`      | `default`  | API key + PostgreSQL connection string                  |
| `maxterview-secrets`   | `default`  | Neon DSN + Clerk/LLM/Stripe env, injected via `envFrom` |
| `repo-secret`          | `argocd`   | ArgoCD repo credentials (private repo)                  |
| `postgres-credentials` | `database` | PostgreSQL password (k3s only)                          |

## Nix Dev Shell

```bash
nix develop        # enter the flake shell (pinned via flake.lock)
direnv allow       # or: auto-load on cd (also pulls + exports KUBECONFIG)
```

| Tool        | Purpose                     |
| ----------- | --------------------------- |
| `terraform` | Infrastructure provisioning |
| `kubectl`   | Kubernetes management       |
| `argocd`    | ArgoCD CLI                  |
| `doctl`     | DigitalOcean CLI (fallback) |
| `infisical` | Secret management CLI       |
| `aws-nuke`  | Last-resort account cleanup |

## Security

- Secrets live in **Infisical**, injected via `infisical run` — never in a committed key. `.gitignore` drops `secrets.tfvars`, `*.tfvars`, `kubeconfig`, `.infisical.json`; `secrets.tfvars.example` is dummy and safe to commit.

### Folder layout (consumer / source)

`infisical run --path` reads exactly **one** folder and does **not** recurse, and `${...}` references resolve
only **within the same folder** on CLI 0.41.x (cross-folder refs store verbatim — verified 2026-09-12).
So a consumer folder must hold every key its target needs; `*_source` folders are reference copies.

| Path                   | Holds                                                     | Read by                                                        |
| ---------------------- | --------------------------------------------------------- | -------------------------------------------------------------- |
| `/consumers/terraform` | `TF_VAR_*` (incl. `TF_VAR_MAXTERVIEW_*`), `AWS_*`         | `make init/plan/apply MOD=…` (`SECRETS_PATH`)                  |
| `/consumers/ansible`   | cloudflare / github / tailscale / slack creds             | `make -C ~/ansible strap-pi\|tailscale-pi*`                    |
| `/sources/github`      | `GITHUB_*`                                                | nothing yet — duplicate of the `TF_VAR_*` pair                 |
| `/sources/cloudflare`  | `CLOUDFLARE_TOKEN`, `R2_ACCOUNT_ID`, `R2_BUCKET`, `AWS_*` | nothing yet (its `AWS_*` are R2 creds — misnamed per ADR 0001) |
| `/sources/tailscale`   | `TAILSCALE_AUTH_*`                                        | nothing yet                                                    |
| `/sources/webhooks`    | `ALERTMANAGER_SLACK_WEBHOOK`                              | nothing yet                                                    |

`/sources/*` are candidates for deletion (their `GITHUB_*`/`CLOUDFLARE_TOKEN` values are byte-identical to the
`/consumers/terraform` copies — verified by hash) or for a CLI upgrade that makes `${folder.KEY}` work.

- GitHub PAT / credentials are written straight to K8s secrets — they never sit in Terraform state.
- R2 backend creds are `TF_VAR_R2_*`, AWS creds `AWS_*`; the endpoint split is handled by the `infra/aws` provider pin (see [Remote state](#remote-state-r2--locking)).
- Cloudflare token (`cfat_…`, `Zone→DNS→Edit`) is currently an account-wide `terraform-admin` token — broad. Works, but not least-privilege. Tighter posture: mint a zone-scoped `seekeru.tech` token and update Infisical.

## Cleanup

```bash
make destroy MOD=doks
make destroy MOD=k3s
make destroy MOD=aws
```

Each module destroys independently.

### Cost control (do NOT skip)

Teardown the AWS module with `make destroy MOD=aws` — **not** aws-nuke. `destroy` removes managed resources in dependency order and empties R2 state so a stale `plan` can't recreate them. Cost alarms (`zero_spend` at plan, `credit_cap` at 95% actual / 90% forecast) email via the `billing-alerts` SNS topic — trust them as the tripwire for normal exits.

### aws-nuke — last-resort orphan cleanup (NOT routine teardown)

Only for resources **not in Terraform state** (manual experiments, leaked drift) that `destroy` never touches. No tag-based opt-out and no `mfa` gate — a genuinely one-way door.

```bash
make nuke-list              # dry-run only: prints what WOULD be deleted, deletes nothing
# after reviewing nuke-list, destructive reset is BY HAND (no make target):
make destroy MOD=aws
infisical run --path /consumers/terraform --env dev -- aws-nuke -c nuke-config.yaml --no-dry-run
```

`nuke-config.yaml` fences KMS + IAM (`resource-types.excludes`) so the sweep can't orphan the credential chain Terraform needs to reprovision. Nuke does not stop future bills — keep provisioning in Terraform and rely on the alarms as the tripwire.

---

## License

MIT. See [LICENSE](LICENSE).
