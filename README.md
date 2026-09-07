# Terraform — Personal Cloud Infrastructure

> Infrastructure-as-Code for my personal cloud environment.  
> **Providers:** DigitalOcean / Cloudflare (R2 + DNS) / AWS · **Provisioner:** Terraform · **Orchestrator:** ArgoCD
> **AI usage is encouraged.** This repo is designed to be AI-friendly: ask an agent to explain, plan, audit, or change infrastructure. Architecture always ends with **a human owner in the loop** — no change is applied without human review of a `plan`. AI is an helper not a dependancy.

---

## Prerequisites

| Requirement            | Details                                                                                            |
| ---------------------- | -------------------------------------------------------------------------------------------------- |
| **Terraform**          | `>= 1.0` ([install guide](https://developer.hashicorp.com/terraform/install))                      |
| **DigitalOcean Token** | Fine-grained PAT with write scope (`DO_TOKEN`) — needed only for `doks`                            |
| **Cloudflare token**   | API token with `Zone → DNS → Edit` (`TF_VAR_CLOUDFLARE_API_TOKEN`) — needed by `cloudflare` module |
| **k3s**                | An existing k3s cluster with `~/.kube/config` — see [K3s Module](#k3s-module-local)                |
| **Make**               | (Optional) `make` for the workflow targets below                                                   |
| **Nix**                | (Optional) `nix develop` for an isolated dev shell — see [Nix Dev Shell](#nix-dev-shell)           |
| **direnv**             | (Optional) Auto-loads the Nix shell, pulls latest, and exports `KUBECONFIG` on `cd`                |

---

## State Management

State lives in a **Cloudflare R2 bucket** (`s3` backend, S3-compatible) with a per-module key — no committed local `terraform.tfstate`.

| Module       | State key                                | Backend |
| ------------ | ---------------------------------------- | ------- |
| `doks`       | `terraform/doks/terraform.tfstate`       | s3      |
| `k3s`        | `terraform/k3s/terraform.tfstate`        | s3      |
| `aws`        | `terraform/aws/terraform.tfstate`        | s3      |
| `cloudflare` | `terraform/cloudflare/terraform.tfstate` | s3      |

**First-time / after backend change** — push local state up (per module):

```bash
make migrate MOD=k3s    # type "yes" to copy local state into R2
```

Backend config lives in each module's `versions.tf` stub (`backend "s3" {}`) plus a committed per-module template `infra/<MOD>/backend.tfbackend.tpl` that is the **single source of truth** for structural config once merged at `init`. The template holds `bucket`, `key`, `region`, `endpoints.s3`, and the `skip_*`/`use_lockfile` flags; the R2 account id in `endpoints.s3` is substituted at `init`-time from the Infisical var `TF_VAR_R2_ACCOUNT_ID` via `scripts/render-tfbackend.sh`. Only the secret keys (`access_key`/`secret_key`, from `TF_VAR_R2_ACCESS_KEY_ID`/`TF_VAR_R2_SECRET_ACCESS_KEY`) are passed as separate `-backend-config` flags. The endpoint is **not** injected as an ambient `AWS_ENDPOINT_URL_S3`, so nothing leaks the R2 endpoint to the AWS provider. The `aws` module keeps its **real** AWS provider creds (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`) separate from the R2 creds to avoid the collision in `docs/incident-2026-08-27-r2-backend-credential-conflict.md`. After `init`, the binding is cached in `infra/<MOD>/.terraform/`, so later `plan`/`apply`/`destroy` pick it up automatically. For the _why_ behind this design and the old-vs-new comparison, see **ADR 0001** (`docs/adr/0001-r2-endpoint-via-per-module-tfbackend.md`). Local `infra/<MOD>/terraform.tfstate*` files are gitignored; after migration, primary state lives in R2 only.

## Locking

Opt-in per module via `use_lockfile = true` in each module's `infra/<MOD>/backend.tfbackend.tpl`, merged into the backend at `init`. R2 has no DynamoDB service, so only the S3-native lockfile (`<key>.tflock`, conditional `PutObject`) is viable — the `dynamodb_table` path can't be used. Verified working on this R2 bucket (2026-09-06, `aws` module): a concurrent `plan -lock-timeout=5s` failed with `Error acquiring the state lock` / HTTP `412 PreconditionFailed`. All four modules share the one `terraform-state` bucket, so one test covers them. Locking guards only concurrent Terraform runs on the **same** module's state — it does **not** stop out-of-band destructive changes (`make nuke-list`, console edits, `aws-nuke`).

**Gotchas**

1. **`plan` locks too** — a read-only `plan` holds the state lock through refresh+plan. Two parallel `plan`s serialize; the second waits up to `-lock-timeout`, then errors.
2. **Per-module locks** — state keys differ, so applies on _different_ modules are not mutually blocked (`aws` && `k3s` can run together); only two runs of the _same_ module serialize.
3. **R2-scoped verification** — the 412 enforcement is store-specific; re-test if the backend ever moves to MinIO/local S3.
4. **Stale lock blocks all runs** — after a crash, later runs fail until the lease expires or you `terraform force-unlock <LOCK_ID>` (ID is in the error). `-lock=false` is an emergency bypass only.
5. **No CI serialization** — dispatch is manual `make apply`; locking is the only guard. Follow the operating rules below.

**Clearing a stale lock:**

```bash
# OFFICIAL ONLY if you are certain no apply is live: the lock ID comes from the error
# infisical run --path /terraform --env dev -- \
#   terraform -chdir=infra/aws force-unlock <LOCK_ID>
```

**Operating rules**

- One `apply`/`destroy` per module at a time (different modules in parallel are fine).
- Run with `-lock-timeout=30s` so a contended/stale lock fails fast with a clear message instead of hanging.

## No CI/CD is deliberate

This is a **single-owner sandbox**: applies are human-gated (`make apply` prompts; the workflow requires a human-reviewed `plan`), and the R2 `use_lockfile` guard already serializes concurrent applies of the same module. Adding a plan→approve→apply pipeline now would add a runner, a CI credential surface, and deploy latency for zero extra safety.

Re-introduce orchestration **only if** a second person/machine needs `apply` access, or you need non-interactive reviewed deploys — then escalate: (1) a single centralized apply path, (2) Atlantis/Spacelift/Terraform Cloud for PR-driven apply/policy/audit.

> Full rationale, trade-offs, and deciding triggers: **ADR 0002** (`docs/adr/0002-no-cicd-manual-human-gated-applies.md`).

---

## Quickstart

```bash
# 1. Clone & enter
cd terraform

# 2. Secrets come from Infisical (see .envrc / SECRETS_PATH=... in the Makefile).
#    There is no secrets.tfvars-driven flow — all tfvars-style inputs flow via infisical run.

# 3. Initialize a module (doks, k3s, aws, or cloudflare) — pulls providers + binds R2 backend
#    If you need k3s then you need to install k3s software
make init MOD=k3s

# 4. Preview
make plan MOD=k3s

# 5. Apply
make apply MOD=k3s
```

### Fresh clone on a new device

The repo is **operator-reproducible, not fresh-clone-self-contained**. Before `make init`/`plan` works, on a new machine you need (none of it ships in this repo, by design):

1. **Infisical identity** — copy `~/.config/infisical/` from an existing device (or `infisical login`), plus this workspace's local `.infisical.json` (`/terraform` dev).
2. **Secrets populated** — the Infisical project must hold all `TF_VAR_*`/`AWS_*` the module needs (see each `variables.tf` + the `Makefile` targets), including the R2 set: `TF_VAR_R2_ACCOUNT_ID`, `TF_VAR_R2_ACCESS_KEY_ID`, `TF_VAR_R2_SECRET_ACCESS_KEY`. (The bucket name `terraform-state` and the endpoint shape live in the committed `backend.tfbackend.tpl`; the account id is substituted by `scripts/render-tfbackend.sh`, so the endpoint is not a standalone env secret.)
3. **R2 state bucket live** — creds in Infisical must still point at the existing `terraform-state` bucket (state stays in R2, not the repo).
4. **`gitops/` repo checked out at `../gitops/`** — `doks`/`k3s` read `app.yaml` via `file()` at apply time, so a missing path fails the ArgoCD-manifest step.
5. **ArgoCD/GHCR repos reachable** — the PAT in Infisical must still be valid for the private `gitops` repo.

Then: `make init MOD=<m>` binds R2 and re-fetches providers. Note `.terraform.lock.hcl` is gitignored, so first `init` on a new machine re-resolves provider versions against the `~>` floors (a minor drift vector, not a blocker), and `.gitignore` also drops any local `*.tfstate`.

---

## Project Layout

```
terraform/
├── infra/                   # Terraform root modules
│   ├── doks/                #   state #1 — DOKS cluster (cloud)
│   │   ├── versions.tf      #   DO, helm, k8s, kubectl, local
│   │   ├── provider.tf      #   DO + dynamic k8s/helm/kubectl providers
│   │   ├── variables.tf     #   DO_TOKEN, CLOUDFLARE_TOKEN, GITHUB_*, DIAGRAM_API_KEY
│   │   └── main.tf          #   cluster → managed PG → helm releases → secrets → argocd app
│   ├── k3s/                 #   state #2 — local k3s cluster (no DO)
│   │   ├── versions.tf      #   helm, k8s, kubectl only
│   │   ├── provider.tf      #   providers read from ~/.kube/config
│   │   ├── variables.tf     #   CLOUDFLARE_TOKEN, GITHUB_*, DIAGRAM_API_KEY, POSTGRES_PASSWORD
│   │   └── main.tf          #   helm releases → self-hosted PG StatefulSet → secrets → argocd app
│   ├── aws/                 #   state #3 — AWS sandbox (S3, RDS, VPC, ASG, CloudFront)
│   │   ├── versions.tf      #   aws + aliased cloudflare providers + s3(R2) backend
│   │   ├── provider.tf      #   aws provider, region + default tags
│   │   ├── variables.tf     #   instance classes, POSTGRES_PASSWORD, ALERT_EMAIL
│   │   ├── vpc.tf           #   VPC, subnets, route tables, IGW
│   │   ├── compute.tf       #   launch template, ASG, ALB
│   │   ├── storage.tf       #   S3 bucket + CloudFront (OAC)
│   │   ├── database.tf      #   RDS PostgreSQL
│   │   ├── security.tf      #   security groups + IAM
│   │   ├── monitoring.tf    #   CloudWatch alarms + budget
│   │   ├── secrets.tf       #   SSM parameters
│   │   └── outputs.tf       #   ALB DNS + CloudFront domain
│   └── cloudflare/          #   state #4 — Cloudflare DNS + zone settings
│       ├── versions.tf      #   cloudflare provider (~>5) + s3(R2) backend
│       ├── provider.tf      #   cloudflare provider (api_token)
│       ├── variables.tf     #   zones, records, zone_settings overrides
│       ├── main.tf          #   cloudflare_dns_record per declared record
│       └── README.md        #   import-first adoption runbook
├── secrets.tfvars           # Legacy gitignored file (not the live secret source)
├── Makefile                 # Workflow shortcuts (accepts MOD=, ENV=, SECRETS_PATH=)
├── flake.nix                # Nix dev shell definition
├── .envrc                   # direnv: auto-nix + git pull + KUBECONFIG
```

---

## Makefile Workflow

Module targets accept `MOD=doks`, `MOD=k3s`, `MOD=aws`, or `MOD=cloudflare`. The `infra/` prefix and Infisical secret flow are baked into each target. Sensitive vars (incl. the R2 credentials backing state) come from `infisical run`. Backend-facing targets (`init`, `upgradeinit`, `reconfigure`, `migrate`) first run `scripts/render-tfbackend.sh` to render `infra/$(MOD)/backend.tfbackend.tpl` (substituting the R2 account id from `$TF_VAR_R2_ACCOUNT_ID`) into a gitignored `.tfbackend`, then exec terraform through `/bin/sh -c` so the `$TF_VAR_R2_ACCESS_KEY_ID`/`$TF_VAR_R2_SECRET_ACCESS_KEY` cred flags expand from infisical's injected env (infisical itself execs directly and would pass them through unexpanded). plan/apply/refresh/destroy exec through a small guard that `unset`s any ambient R2 endpoint vars (`AWS_ENDPOINT_URL_S3`/`AWS_ENDPOINT_URL`/`AWS_S3_ENDPOINT`), so the AWS provider never sees an R2 endpoint and uses real AWS creds even if a stale secret is present in Infisical. `nuke-list` is account-scoped (ignores `MOD`) and runs from the repo root.

| Target             | Command                                                                                                        | Description                              |
| ------------------ | -------------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| `make init`        | `infisical run -- /bin/sh -c 'render-tfbackend.sh && terraform ... init -backend-config=<gen>'`                | Init providers + bind R2 backend         |
| `make upgradeinit` | `infisical run -- /bin/sh -c 'render-tfbackend.sh && terraform ... init -upgrade -backend-config=<gen>'`       | Upgrade providers / re-bind backend      |
| `make plan`        | `infisical run -- terraform -chdir=infra/$(MOD) plan`                                                          | Preview changes                          |
| `make apply`       | `infisical run -- terraform -chdir=infra/$(MOD) apply`                                                         | Apply changes                            |
| `make destroy`     | `infisical run -- terraform -chdir=infra/$(MOD) destroy`                                                       | Tear down resources                      |
| `make fmt`         | `terraform -chdir=infra/$(MOD) fmt`                                                                            | Format all `.tf` files                   |
| `make validate`    | `terraform -chdir=infra/$(MOD) validate`                                                                       | Validate configuration                   |
| `make migrate`     | `infisical run -- /bin/sh -c 'render-tfbackend.sh && terraform ... init -migrate-state -backend-config=<gen>'` | One-time: push local state to R2         |
| `make dump`        | `kubectl exec ... pg_dump \| gzip > ~/backups/`                                                                | Backup diagramdb from local k3s postgres |
| `make nuke-list`   | `infisical run -- aws-nuke -c nuke-config.yaml (dry-run)`                                                      | Dry-run aws-nuke sweep (deletes nothing) |

**Variables:**

| Variable       | Default      | Description                                                |
| -------------- | ------------ | ---------------------------------------------------------- |
| `MOD`          | (empty)      | Module subdirectory: `doks`, `k3s`, `aws`, or `cloudflare` |
| `ENV`          | `dev`        | Infisical environment                                      |
| `SECRETS_PATH` | `/terraform` | Infisical secrets path                                     |

**Examples:**

```bash
make init MOD=k3s       # first time for a module
make plan MOD=k3s       # preview
make apply MOD=k3s      # apply
make plan MOD=doks      # another module
make plan MOD=cloudflare # preview cloudflare DNS changes
make apply MOD=cloudflare # apply cloudflare DNS changes
make migrate MOD=k3s    # one-time local→R2 state copy
```

---

## Variables

All Terraform input variables live in the module `variables.tf` files — `infra/doks/variables.tf`, `infra/k3s/variables.tf`, `infra/aws/variables.tf`, `infra/cloudflare/variables.tf` — and carry their own `sensitive = true` flags and `optional()` object schemas. Read the source for the authoritative type/required/default split.

> Secrets are injected from Infisical (the `infisical run` wrapper in the Makefile) and mapped to Terraform input vars as `TF_VAR_*`. A `secrets.tfvars.example` template is kept for reference, but it is not the live secret source.

---

## DOKS Cluster (Cloud)

| Attribute     | Value                | Notes                        |
| ------------- | -------------------- | ---------------------------- |
| **Name**      | `lab-cluster`        | Singleton — one cluster only |
| **Region**    | `var.default_region` | Inherits `sgp1` default      |
| **Version**   | `1.34.8-do.2`        | DO-managed Kubernetes        |
| **Node pool** | 3 × `s-2vcpu-2gb`    | Worker-pool, 6 GB total      |

### Usage

The kubeconfig is written to `~/kubeconfig` at apply time:

```bash
export KUBECONFIG=~/kubeconfig
kubectl get nodes
```

### Database

A DigitalOcean managed PostgreSQL 16 (`db-s-1vcpu-1gb`) is provisioned in the same VPC as the cluster. Credentials injected into `diagram-secrets` with `sslmode=no-verify` for private VPC connectivity.

---

## K3s Module (Local)

For local development or edge deployments. Runs against an existing k3s cluster — reads `~/.kube/config` directly.

| Aspect                | Detail                                                                                               |
| --------------------- | ---------------------------------------------------------------------------------------------------- |
| **No DO dependency**  | All providers point at local kubeconfig                                                              |
| **Database**          | Self-hosted PostgreSQL 16 StatefulSet in `database` namespace, 5Gi PVC on `local-path` storage class |
| **Connection string** | `postgresql://diagram:${pass}@postgres.database.svc.cluster.local:5432/diagramdb`                    |

### Init & Apply

```bash
make init MOD=k3s
make plan MOD=k3s
make apply MOD=k3s
```

Requires Infisical secrets populated with `POSTGRES_PASSWORD`, `CLOUDFLARE_TOKEN`, `GITHUB_PAT`, and `DIAGRAM_API_KEY`.

### DB backup

Before any destructive operation (`make destroy MOD=k3s`), dump the database:

```bash
make dump   # → ~/backups/diagramdb-<timestamp>.sql.gz
```

---

## AWS Module (Cloud)

An AWS sandbox architecture (`infra/aws/`, state #3): VPC, public subnets, auto-scaling EC2 web
tier behind an Application Load Balancer, private single-AZ RDS PostgreSQL, and an S3 bucket
served via CloudFront. Provisioning targets a real AWS account; state still lives in R2.

### Credentials required

Requires Infisical secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (AWS account),

`TF_VAR_ALERT_EMAIL` (SNS alert email), and the `TF_VAR_R2_*` backend pair.

Web tier: EC2 instances in an Auto Scaling Group (target-tracking on CPU) registered to an
Application Load Balancer with ELB health checks. Static assets: private S3 bucket served through
CloudFront via Origin Access Control (OAC). Alerting: a CloudWatch CPU alarm plus zero-spend and
credit-cap budgets all publish to the SNS topic (`TF_VAR_ALERT_EMAIL` must confirm the subscription
once).

HTTPS is optional: set `alb_domain` (here `alb.seekeru.tech`) and the cert issues fully
automatically — `infra/aws` brings in an aliased `cloudflare` provider that creates the
`alb.seekeru.tech` CNAME (tracking the real ALB DNS) plus the ACM validation CNAME from
`aws_acm_certificate.domain_validation_options`, then `aws_acm_certificate_validation` poll
until ISSUED before binding :443. No manual Cloudflare step; see `compute.tf`. The ALB DNS
records are deliberately kept in `infra/aws` (not the `infra/cloudflare` module, which owns
the tunnel hostnames) so each module is self-contained. See `AWS.md` for the full architecture.

### Deployment notes (verified)

- **Live endpoints:** `https://alb.seekeru.tech` (200, nginx) · `http://alb.seekeru.tech` (301 → HTTPS) · CloudFront `https://d14f3y8b1rk8te.cloudfront.net`.
- **Provider vs. R2 endpoint:** the R2 remote-state endpoint is delivered only to the backend, via the per-module `backend.tfbackend.tpl` rendered at init — never as an ambient `AWS_ENDPOINT_URL_S3`. The stale `AWS_ENDPOINT_URL_S3` Infisical secret was removed, and the Makefile `plan`/`apply` targets additionally `unset` it defensively. So the AWS provider in `provider.tf` needs **no** `endpoints.s3` override; real `aws_s3_bucket`/`aws_s3_bucket_policy` calls resolve to AWS by default. Do not reintroduce `AWS_ENDPOINT_URL_S3` into the runtime env, or the `access key has length 20, should be 32` / R2-routing bug returns.
- **DB user:** `dbadmin` (PostgreSQL reserves `admin`).
- **Apply is non-interactive:** `make apply MOD=aws` prompts; use `terraform -chdir=infra/aws apply -auto-approve` (or pipe) for headless runs.
- **Upgrade + revalidation matrix:** see `AWS.md` §8 for ranked upgrade paths and the drift-check commands.

---

## Cloudflare Module (DNS)

The `infra/cloudflare/` module (state #4) makes the tunnel-facing DNS records declarative so you do not need the Cloudflare dashboard for them. Provider: `cloudflare/cloudflare ~> 5.0`; state lives in R2 like every other module.

### Scope

Manages the **4 tunnel hostnames** on `seekeru.tech` (zone id `5a1a5f826d5a3398dc78ba360e24dfa0`):

| Record                   | Type  | Target                       | Proxied |
| ------------------------ | ----- | ---------------------------- | ------- |
| `seekeru.tech` (apex)    | CNAME | `7bbbb5d4-…cfargotunnel.com` | yes     |
| `portfolio.seekeru.tech` | CNAME | `7bbbb5d4-…cfargotunnel.com` | yes     |
| `diagram.seekeru.tech`   | CNAME | `7bbbb5d4-…cfargotunnel.com` | yes     |
| `max.seekeru.tech`       | CNAME | `7bbbb5d4-…cfargotunnel.com` | yes     |

These were imported into state first (adopt, don't overwrite) and are now tracked by Terraform.

**Left in the dashboard** (out of TF scope, owned by other systems):

- Clerk SaaS records (`accounts`, `clerk`, `clk._domainkey`, `clkmail` …)
- AWS ALB `alb.seekeru.tech` + its ACM validation CNAME (owned by `infra/aws`)
- Any future statically-addressed record

### Credentials

Needs `TF_VAR_CLOUDFLARE_API_TOKEN` (a `cfat_…` API token with `Zone → DNS → Edit`; account-wide is acceptable here). `TF_VAR_CLOUDFLARE_ACCOUNT_ID` is also stored in Infisical but is not consumed by the DNS-only provider path. Both are injected via Infisical — never committed.

### Workflow

```bash
make init MOD=cloudflare
make plan MOD=cloudflare   # propose DNS changes
make apply MOD=cloudflare  # apply the diff
```

To add a hostname, drop a map entry under `records` in `infra/cloudflare/variables.tf`, then `plan`/`apply`. To remove one you no longer run (e.g. a dead tunnel host), delete the map entry — Terraform will delete the record. See `infra/cloudflare/README.md` for the full adoption runbook and how to `terraform import` future records that were created dashboard-side.

## ArgoCD

Installed via the `argoproj/argo-helm` chart at version `7.7.0` in the `argocd` namespace, alongside Kubernetes secrets and a root Application CR.

### Bootstrap flow

1. Terraform deploys Helm charts + secrets
2. Terraform applies the root Application manifest via the `kubectl` provider — this is the **only** manifest applied directly
3. That root Application tells ArgoCD to sync the rest from the GitOps repo

The manifest path defaults to `${path.module}/../../../gitops/app.yaml` (resolved at plan time) but can be overridden via `app_yaml_path`. See `infra/k3s/variables.tf` and `infra/doks/variables.tf`.

### CLI setup

```bash
## PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d) && echo -e "\n---> Local Login: https://localhost:8080\n---> Network Login: https://<YOUR_COMPUTER_IP>:8080\n---> Username: admin\n---> Password: $PASS\n" && kubectl port-forward svc/argocd-server -n argocd --address 0.0.0.0 8080:443
```

## Managed Database (PostgreSQL)

Database strategy varies by module: **DO Managed PG** for `doks` (see [DOKS Cluster](#doks-cluster-cloud)), **self-hosted StatefulSet** for `k3s` (see [K3s Module](#k3s-module-local)).
The connection string and API key are injected into the `diagram-secrets` Kubernetes secret consumed by application pods.
Related docs:

- `docs/incident-2026-09-03-postgres-credential-mismatch.md` — root cause + merged rotation runbook: a manual `ALTER USER` split the role password from `diagram-secrets` and broke backend auth over TCP (no data loss); includes the safe rotate-via-Terraform procedure.

---

## Kubernetes Secrets

The following secrets are created automatically by Terraform (no manual `kubectl create secret` needed):

| Secret Name            | Namespace  | Purpose                                      |
| ---------------------- | ---------- | -------------------------------------------- |
| `cloudflared-token`    | `default`  | Cloudflare Tunnel token for `cloudflared`    |
| `ghcr-login`           | `default`  | Docker registry credentials for GHCR         |
| `diagram-secrets`      | `default`  | API key + PostgreSQL connection string       |
| `repo-secret`          | `argocd`   | ArgoCD repository credentials (private repo) |
| `postgres-credentials` | `database` | PostgreSQL password (k3s only)               |

---

## Nix Dev Shell

A Nix flake (`flake.nix`) provides a reproducible developer environment. All tools are pinned via the flake lock:

```bash
# Enter the dev shell
nix develop

# Or with direnv (automatic on cd)
direnv allow
```

| Tool        | Purpose                     |
| ----------- | --------------------------- |
| `terraform` | Infrastructure provisioning |
| `kubectl`   | Kubernetes management       |
| `argocd`    | ArgoCD CLI                  |
| `doctl`     | DigitalOcean CLI (fallback) |
| `infisical` | Secret management CLI       |
| `aws-nuke`  | Last-resort account cleanup |

---

## Security

- **Secrets are managed in Infisical**, injected via `infisical run` — they never sit in a committed `.tfvars` file. The `secrets.tfvars.example` template is dummy/empty and safe to commit.
- The DO token is consumed via `var.DO_TOKEN` (marked `sensitive = true`).
- GitHub PAT and credentials are written directly to Kubernetes secrets — they never leave the Terraform state.
- The Cloudflare module uses `TF_VAR_CLOUDFLARE_API_TOKEN` (provider) with `Zone → DNS → Edit`. The current key is an account**-wide** `terraform-admin` token (broad). It works, but it is not least-privilege; if you want a tighter posture later, mint a token scoped to just the `seekeru.tech` zone (`Zone:DNS:Edit`) and update the Infisical value.
- R2 state-backend creds are namespaced `TF_VAR_R2_*` and the R2 endpoint is rendered into each module's backend template at init — neither is shipped as an ambient `AWS_ENDPOINT_URL_S3`/real-AWS `AWS_*` env var — keeping R2 creds distinct from the real AWS provider creds (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`). This is the fix for `docs/incident-2026-08-27-r2-backend-credential-conflict.md`.
- `secrets.tfvars`, `*.tfvars`, `kubeconfig`, and `.infisical.json` are all in `.gitignore`.
- `secrets.tfvars.example` is safe to commit — it has dummy/empty values for all secrets.
- Consider GitLeaks + pre-commit hooks to prevent accidental secret commits.

---

## Cleanup

```bash
make destroy MOD=doks
make destroy MOD=k3s
make destroy MOD=aws
```

Each module is destroyed independently.

### Cost control (do NOT skip)

A controlled teardown — `make destroy MOD=aws` — not aws-nuke, is how you exit the
AWS module cleanly: `terraform destroy` tears down what it manages in dependency
order and empties the R2-backed state so resources cannot be re-created by a
stale `plan`. Cost alarms (in `infra/aws/monitoring.tf`) are your real tripwire:
`zero_spend` (100% of limit) and `credit_cap` (95% actual / 90% forecasted)
email via the `billing-alerts` SNS topic. Trust destroy + alarms for normal exits.

### aws-nuke — last-resort orphan cleanup (NOT routine teardown)

`aws-nuke` is only for removing resources **not tracked in Terraform state**
(manual console experiments, leaked drift) that `destroy` will never touch. It
has no tag-based opt-out and no `mfa` gate is configured, so it is a genuinely
dangerous one-way door.

- `make nuke-list` — **dry-run only**; prints what WOULD be deleted, deletes nothing.
- Destructive reset is deliberately **not** a `make` target; run it by hand:

```bash
make destroy MOD=aws
# then, only after reviewing make nuke-list output:
infisical run --path /terraform --env dev -- \
    aws-nuke -c nuke-config.yaml --no-dry-run
```

- The config fences KMS + IAM (`resource-types.excludes` in `nuke-config.yaml`) so
  the sweep won't orphan the credential chain Terraform needs to reprovision.
- Nuke does **not** stop future bills. Prevent cost by keeping provisioning in
  Terraform and using the alarms above as the tripwire.

---

## License

MIT. See [LICENSE](LICENSE).
