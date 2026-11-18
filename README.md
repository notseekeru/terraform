# Terraform — Personal Cloud Infrastructure

> Infrastructure-as-Code for my personal cloud environment.
> **Providers:** Cloudflare (R2 + DNS) / AWS · **Provisioner:** Terraform · **Orchestrator:** ArgoCD
> **AI usage is encouraged** — ask an agent to explain, audit, or change infra. Every change still ends with a human-reviewed `plan`; AI is a helper, not a dependency.

---

## Prerequisites

| Requirement          | Details                                                                                    |
| -------------------- | ------------------------------------------------------------------------------------------ |
| **Terraform**        | `>= 1.0` ([install](https://developer.hashicorp.com/terraform/install))                    |
| **Cloudflare token** | API token `Zone → DNS → Edit` (`TF_VAR_CLOUDFLARE_API_TOKEN`) — for `cloudflare` and `aws` |
| **k3s**              | Existing k3s cluster with `~/.kube/config` — see [K3s Module](#k3s-module-local)           |
| **Nix / direnv**     | Optional: `nix develop` shell; `direnv` auto-loads it, pulls, exports `KUBECONFIG`         |

`make` is optional (workflow targets). Secrets are not shipped in the repo — see [Fresh clone](#fresh-clone-on-a-new-device).

## Quickstart

```bash
cd terraform

# Secrets come from Infisical: every Makefile target runs `infisical run` itself; there is no secrets.tfvars flow.
make init MOD=k3s    # init providers + bind R2 backend
make plan MOD=k3s    # preview
make apply MOD=k3s   # apply
```

### Fresh clone on a new device

The repo is operator-reproducible, not fresh-clone-self-contained. Before init/plan works on a new machine (none of this ships in the repo, by design):

1. **Infisical identity** — copy `~/.config/infisical/` from a working device (or `infisical login`) plus this workspace's `.infisical.json` (path `/consumers/terraform`, env `prod`).
2. **Secrets populated** — the Infisical project must hold the `TF_VAR_*`/`AWS_*` vars each module's `variables.tf` needs, incl. the R2 set (`TF_VAR_R2_*`) and ambient `AWS_ENDPOINT_URL_S3`.
3. **R2 state bucket live** — creds must still point at the existing `terraform-state` bucket.
4. **`gitops/` repo checked out at `../gitops/`** — `k3s` reads `app.yaml` via `file()` at apply time.
5. **ArgoCD/GHCR reachable** — the PAT in Infisical must still be valid for the private `gitops` repo.

Then `make init MOD=<m>` re-fetches providers. `.terraform.lock.hcl` and local `*.tfstate` are gitignored, so first init on a machine re-resolves against `~>` floors (a minor drift vector).

---

## K3s Module (Local)

Runs against an existing k3s cluster via `~/.kube/config`. This is the deployment target.

| Aspect                | Detail                                                                            |
| --------------------- | --------------------------------------------------------------------------------- |
| **Database**          | Self-hosted PG 18 StatefulSet, `database` ns, 5Gi PVC on `local-path`             |
| **Connection string** | `postgresql://diagram:${pass}@postgres.database.svc.cluster.local:5432/diagramdb` |

```bash
make init MOD=k3s && make plan MOD=k3s && make apply MOD=k3s
```

- `docs/incident-2026-10-05-nodefs-disk-pressure-eviction.md` — the kubelet evicted every 10s for 10 hours on nodefs pressure while `systemctl restart k3s` made it look fixed. Read before debugging "ArgoCD keeps crashing" or a missing PreSync hook.
- `docs/incident-2026-10-12-container-name-reservation-livelock.md` — a power cut left 6 pods in `CreateContainerError` for 2h14m while their containers kept running. Read before debugging "ArgoCD is degraded" that arrives with a dead database, metrics-server and tunnel.
- `docs/incident-2026-10-15-argocd-3-upgrade-node-stall.md` — the chart 7.7.0 to 10.10.5 bump pulled 1GB of images, stalled the Pi twice and left CoreDNS with no endpoints, while three applies failed on API timeouts after the manifests were already applied. Read before debugging a helm release stuck in `pending-upgrade` or `failed`, or a chart bump that hits its timeout.

Needs Infisical secrets: `POSTGRES_PASSWORD`, `CLOUDFLARE_TOKEN`, `GITHUB_PAT`, `DIAGRAM_API_KEY`, plus the
maxterview set below. Back up the DB before `destroy`:

```bash
make dump   # → ~/backups/diagramdb-<timestamp>.sql.gz
```

## AWS Module (Cloud)

`infra/aws/` (state #2) runs the sesume stack: a VPC with one public and two private subnets, a `t4g.micro` edge instance behind a Cloudflare tunnel (nginx, the tunnel connector, and the NAT for the private subnets), single-AZ encrypted RDS PostgreSQL in the private subnets, an SQS review queue with a dead-letter queue, an ECR repository, Lambda functions for the API, the review worker, migrations and the liveness probe, and a private S3 bucket holding the built frontend. State lives in R2.

**Credentials** (Infisical): `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`, `TF_VAR_POSTGRES_PASSWORD`, `TF_VAR_AUTH_SECRET`, `TF_VAR_DATA_KEY`, `TF_VAR_ORIGIN_TOKEN`, `TF_VAR_ALERT_EMAIL`, `TF_VAR_CLOUDFLARE_ACCOUNT_ID`, `TF_VAR_CLOUDFLARE_API_TOKEN`, `TF_VAR_lambda_image_uri`, `TF_VAR_MAXTERVIEW_LLM_BASE_URL`/`_MODEL`/`_API_KEY` (the server-wide reviewer, shared with maxterview), and the `TF_VAR_R2_*` backend pair.

Notable wiring:

- **No ALB, no NAT gateway, no CloudFront, no ACM.** The tunnel is the front door and the instance does the NAT work with an nft rule; the Cloudflare record is created by this module rather than by `infra/cloudflare`.
- **The edge instance holds no application secret.** It fetches the tunnel and origin tokens from SSM at boot and proxies `/api` to the API Lambda's Function URL.
- **The functions read their config from SSM at cold start** (`/sesume/database_url`, `auth_secret`, `data_key`, `origin_token`, and the `llm_base_url`/`llm_model`/`llm_api_key` trio), so nothing is injected as a Lambda environment variable. `CONFIG_REVISION` carries the parameter versions, so a secret change replaces the warm containers instead of leaving them on the old value. The `llm_*` parameters are the deployment-wide reviewer, filled from the maxterview credentials, so a user who brings no key of their own still gets queued reviews; a stored provider still wins.
- **CI deploys itself** through a GitHub OIDC role (`sesume-cd`): the image to ECR, the migrator rolled and invoked, then the API and worker rolled, then the frontend to the S3 bucket. No stored keys.
- **The database keeps one day of backups, is encrypted at rest, and has deletion protection on.** A `make destroy MOD=aws` fails until that flag is flipped in `infra/aws/database.tf`; the final snapshot is named `sesume-final`, so a second destroy needs that snapshot deleted first.
- **The liveness probe lives outside the VPC** so it can still report when the edge is the broken part. It runs every five minutes and its failures land on `sesume-probe-errors`.
- **One box, one AZ, for now.** It terminates the tunnel and NATs the private subnets, so a reboot is an outage for ingress and for the worker's internet egress. Acceptable at single-owner scale; the path to more users is a second AZ with an ALB and a NAT gateway, or moving the API off the box entirely. Nothing else here assumes one instance.
- **The edge is configured once, at boot.** `edge.sh.tftpl` renders into EC2 user data, so cloud-init runs it on first boot and never again: no drift correction, no routine patching, and a change only lands by replacing the instance (`user_data_replace_on_change`). Failures are only visible in `/var/log/cloud-init-output.log` on the box, reachable through Session Manager.
- **The first apply on a cold account cannot create the functions**, because a container image has to exist first. Apply with `TF_VAR_create_functions=false`, push the image, then apply with it back at its default of `true`. `lambda_image_uri` is only read at creation; CD owns the image afterwards.

## ArgoCD

Installed via `argoproj/argo-helm` in the `argocd` namespace with K8s secrets and a root Application CR.

**Bootstrap:** Terraform applies Helm charts + secrets → applies the root Application via the `kubectl` provider (the **only** direct manifest) → that root App syncs the rest from the GitOps repo. Manifest defaults to `${path.module}/../../../gitops/app.yaml` (resolved at plan time); override via `app_yaml_path` (`infra/k3s/variables.tf`).

```bash
PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d) \
  && kubectl port-forward svc/argocd-server -n argocd --address 0.0.0.0 8080:443
# Login: https://localhost:8080 — admin / $PASS
```

## Databases

- `docs/incident-2026-09-03-postgres-credential-mismatch.md` — a manual `ALTER USER` split the role password from `diagram-secrets` and broke backend auth over TCP (no data loss); includes the safe rotate-via-Terraform procedure.
- `docs/incident-2026-08-27-r2-backend-credential-conflict.md` — the R2/real-AWS credential collision behind the `TF_VAR_R2_*` namespace split.

## Remote state (R2) & locking

State lives in a **Cloudflare R2 bucket** (`s3` backend) under a per-module key — no committed local state.

**How the R2 endpoint is delivered (read once):** the s3 backend and the AWS provider both read the ambient `AWS_*` namespace, so they must be kept from colliding:

- R2 creds stay namespaced `TF_VAR_R2_*` (`TF_VAR_R2_BUCKET`, `..._ACCESS_KEY_ID`, `..._SECRET_ACCESS_KEY`); AWS creds stay `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`. Never use a bare `AWS_*` name for R2 creds.
- The **R2 endpoint** is the ambient `AWS_ENDPOINT_URL_S3`, present on **every** run because the s3 backend needs it to reach R2 (init **and** plan/apply/refresh/destroy). Same var on a fresh box: set it to `https://<account>.r2.cloudflarestorage.com`.
- Because that var is also read by the AWS provider, `infra/aws/provider.tf` pins `endpoints { s3 = "https://s3.ap-southeast-1.amazonaws.com" }`. That pin — not an env `unset` — keeps real `aws_s3_bucket*` calls in AWS.

> **Do not** `unset AWS_ENDPOINT_URL_S3` around plan/apply/refresh/destroy — that starves the backend's own R2 connection. Removing or weakening the `aws` provider pin routes AWS bucket calls to R2 (`access key has length 20, should be 32`). Full rationale + history: **ADR 0001** (`docs/adr/0001-r2-endpoint-ambient-env-provider-pin.md`).

### Operating rules

When no CI stage runs and only `make apply` gates concurrency, follow these:

- One `apply`/`destroy` per module at a time. Different modules can run in parallel (state keys differ; locks are per-module).
- Run with `-lock-timeout=30s` so a contended/stale lock fails fast instead of hanging.
- A read-only `plan` also holds the state lock through refresh+plan; two parallel `plan`s serialize.
- `use_lockfile = true` guards **same-module** Terraform runs only — it does not stop out-of-band destructive changes (`aws-nuke`, console edits).
- Stale lock after a crash: run `terraform force-unlock <LOCK_ID>` (the ID is in the error) once you're sure no apply is live. `-lock=false` is an emergency bypass only.

## Cleanup

```bash
make destroy MOD=k3s
make destroy MOD=aws
```

Each module destroys independently. The AWS module refuses to destroy while `deletion_protection` is on: flip it in `infra/aws/database.tf`, apply, then destroy. Deleting also writes the final snapshot `sesume-final`, and a later destroy collides with it until that snapshot is removed by hand.

### Cost control (do NOT skip)

Teardown the AWS module with `make destroy MOD=aws` — **not** aws-nuke. `destroy` removes managed resources in dependency order and empties R2 state so a stale `plan` can't recreate them. Cost alarms (`sesume-zero-spend` at plan, `sesume-credit-cap` at 95% actual / 90% forecast) email via the `sesume-alerts` SNS topic — trust them as the tripwire for normal exits.

### aws-nuke — last-resort orphan cleanup (NOT routine teardown)

Only for resources **not in Terraform state** (manual experiments, leaked drift) that `destroy` never touches. No tag-based opt-out and no `mfa` gate — a genuinely one-way door.

```bash
make nuke-list              # dry-run only: prints what WOULD be deleted, deletes nothing
# after reviewing nuke-list, destructive reset is BY HAND (no make target):
make destroy MOD=aws
infisical run --path /consumers/terraform --env prod -- aws-nuke -c nuke-config.yaml --no-dry-run
```

`nuke-config.yaml` fences KMS + IAM (`resource-types.excludes`) so the sweep can't orphan the credential chain Terraform needs to reprovision. Nuke does not stop future bills — keep provisioning in Terraform and rely on the alarms as the tripwire.

---

## License

MIT. See [LICENSE](LICENSE).
