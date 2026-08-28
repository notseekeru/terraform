# Terraform — Personal Cloud Infrastructure

> Infrastructure-as-Code for my personal cloud environment.  
> **Providers:** DigitalOcean / Cloudflare R2 / AWS · **Provisioner:** Terraform · **Orchestrator:** ArgoCD

---

## Prerequisites

| Requirement            | Details                                                                                  |
| ---------------------- | ---------------------------------------------------------------------------------------- |
| **Terraform**          | `>= 1.0` ([install guide](https://developer.hashicorp.com/terraform/install))            |
| **DigitalOcean Token** | Fine-grained PAT with write scope (`DO_TOKEN`) — needed only for `doks` / `droplet`      |
| **SSH Keys**           | Public keys uploaded to your DO account or provided inline via `secrets.tfvars`          |
| **k3s**                | An existing k3s cluster with `~/.kube/config` — see [K3s Module](#k3s-module-local)      |
| **Make**               | (Optional) `make` for the workflow targets below                                         |
| **Nix**                | (Optional) `nix develop` for an isolated dev shell — see [Nix Dev Shell](#nix-dev-shell) |
| **direnv**             | (Optional) Auto-loads the Nix shell, pulls latest, and exports `KUBECONFIG` on `cd`      |

---

## State Management

State is stored in a **Cloudflare R2 bucket** (`s3` backend, S3-compatible) — no local `terraform.tfstate` needed. Terraform reads/writes it remotely with a per-module key.

**Storage layout** in the `terraform-state` R2 bucket:

| Module    | State key                             | Backend |
| --------- | ------------------------------------- | ------- |
| `droplet` | `terraform/droplet/terraform.tfstate` | s3      |
| `doks`    | `terraform/doks/terraform.tfstate`    | s3      |
| `k3s`     | `terraform/k3s/terraform.tfstate`     | s3      |
| `aws`     | `terraform/aws/terraform.tfstate`     | s3      |

**Backend config** lives per module in `versions.tf`. The R2 bucket, key, and access/secret keys are passed from Infisical env vars at `init` time via `-backend-config` (`TF_VAR_R2_BUCKET`, `TF_VAR_R2_ACCOUNT_ID`, `TF_VAR_R2_ACCESS_KEY_ID`, `TF_VAR_R2_SECRET_ACCESS_KEY`); the R2 endpoint URL is injected as `AWS_ENDPOINT_URL_S3` (env-var source for the s3 backend's `endpoints.s3`). The AWS-specific module (`infra/aws`) additionally uses real AWS credentials via the native `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` env vars for its provider — kept separate from the R2 creds. See `docs/R2-backend-credential-conflict.md` for the collision that motivated this split.

**First-time setup** (per module, or after changing backend config):

```bash
make migrate MOD=k3s    # e.g. — pushes local state to R2 (type "yes" to copy)
```

The backend binding is cached in `infra/<MOD>/.terraform/terraform.tfstate` after `init`, so subsequent `plan`/`apply`/`destroy` pick it up automatically.

**Caveats**

- Remote state gives Terraform **native locking** — concurrent runs against a module are guarded.
- Splitting R2 creds (`TF_VAR_R2_*` + `AWS_ENDPOINT_URL_S3`) from real AWS creds (`AWS_*`) avoids the `InvalidAccessKeyId` collision documented in `docs/R2-backend-credential-conflict.md`.
- `infra/<MOD>/terraform.tfstate*` local files are gitignored; after migration the primary state is in R2 only.

---

## Quickstart

```bash
# 1. Clone & enter
cd terraform

# 2. Secrets come from Infisical (see .envrc / SECRETS_PATH=... in the Makefile).
#    There is no secrets.tfvars-driven flow — all tfvars-style inputs flow via infisical run.

# 3. Initialize a module (droplet, doks, k3s, or aws) — pulls providers + binds R2 backend
#    If you need k3s then you need to install k3s software
make init MOD=k3s

# 4. Preview
make plan MOD=k3s

# 5. Apply
make apply MOD=k3s
```

---

## Project Layout

```
terraform/
├── infra/                   # Terraform root modules
│   ├── droplet/             #   state #1 — standalone DO droplets
│   │   ├── versions.tf      #   Terraform & DO + local providers
│   │   ├── provider.tf      #   DO provider
│   │   ├── variables.tf     #   DO_TOKEN, ssh_keys, servers, region defaults
│   │   ├── main.tf          #   SSH keys, droplets, Ansible inventory
│   │   ├── inventory.tmpl   #   Ansible inventory template (rendered post-apply)
│   │   └── outputs.tf       #   droplet IPs and attributes
│   ├── doks/                #   state #2 — DOKS cluster (cloud)
│   │   ├── versions.tf      #   DO, helm, k8s, kubectl, local
│   │   ├── provider.tf      #   DO + dynamic k8s/helm/kubectl providers
│   │   ├── variables.tf     #   DO_TOKEN, CLOUDFLARE_TOKEN, GITHUB_*, DIAGRAM_API_KEY
│   │   └── main.tf          #   cluster → managed PG → helm releases → secrets → argocd app
│   ├── k3s/                 #   state #3 — local k3s cluster (no DO)
│   │   ├── versions.tf      #   helm, k8s, kubectl only
│   │   ├── provider.tf      #   providers read from ~/.kube/config
│   │   ├── variables.tf     #   CLOUDFLARE_TOKEN, GITHUB_*, DIAGRAM_API_KEY, POSTGRES_PASSWORD
│   │   └── main.tf          #   helm releases → self-hosted PG StatefulSet → secrets → argocd app
│   └── aws/                 #   state #4 — AWS sandbox (S3, RDS, VPC, ASG, CloudFront)
│       ├── versions.tf      #   aws provider + s3(R2) backend
│       ├── provider.tf      #   aws provider, region + default tags
│       ├── variables.tf     #   instance classes, POSTGRES_PASSWORD, ALERT_EMAIL
│       ├── vpc.tf           #   VPC, subnets, route tables, IGW
│       ├── compute.tf       #   launch template, ASG, ALB
│       ├── storage.tf       #   S3 bucket + CloudFront (OAC)
│       ├── database.tf      #   RDS PostgreSQL
│       ├── security.tf      #   security groups + IAM
│       ├── monitoring.tf    #   CloudWatch alarms + budget
│       ├── secrets.tf       #   SSM parameters
│       └── outputs.tf       #   ALB DNS + CloudFront domain
├── secrets.tfvars           # Legacy gitignored file (not the live secret source)
├── Makefile                 # Workflow shortcuts (accepts MOD=, ENV=, SECRETS_PATH=)
├── flake.nix                # Nix dev shell definition
├── .envrc                   # direnv: auto-nix + git pull + KUBECONFIG
```

---

## Makefile Workflow

All targets accept `MOD=droplet`, `MOD=doks`, `MOD=k3s`, or `MOD=aws`. The `infra/` prefix and Infisical secret flow are baked into each target. Sensitive vars (incl. the R2 credentials backing state) come from `infisical run`. Backend-facing targets (`init`, `upgradeinit`, `migrate`) exec terraform through `/bin/sh -c` so the `TF_VAR_R2_*` refs expand from infisical's injected env; plan/apply/destroy exec directly so the AWS provider sees native `AWS_*` creds.

| Target             | Command                                                                             | Description                              |
| ------------------ | ----------------------------------------------------------------------------------- | ---------------------------------------- |
| `make init`        | `infisical run -- /bin/sh -c 'terraform ... init $(backend_config)'`                | Init providers + bind R2 backend         |
| `make upgradeinit` | `infisical run -- /bin/sh -c 'terraform ... init -upgrade $(backend_config)'`       | Upgrade providers / re-bind backend      |
| `make plan`        | `infisical run -- terraform -chdir=infra/$(MOD) plan`                               | Preview changes                          |
| `make apply`       | `infisical run -- terraform -chdir=infra/$(MOD) apply`                              | Apply changes                            |
| `make destroy`     | `infisical run -- terraform -chdir=infra/$(MOD) destroy`                            | Tear down resources                      |
| `make fmt`         | `terraform -chdir=infra/$(MOD) fmt`                                                 | Format all `.tf` files                   |
| `make validate`    | `terraform -chdir=infra/$(MOD) validate`                                            | Validate configuration                   |
| `make migrate`     | `infisical run -- /bin/sh -c 'terraform ... init -migrate-state $(backend_config)'` | One-time: push local state to R2         |
| `make dump`        | `kubectl exec ... pg_dump \| gzip > ~/backups/`                                     | Backup diagramdb from local k3s postgres |

**Variables:**

| Variable       | Default      | Description                                             |
| -------------- | ------------ | ------------------------------------------------------- |
| `MOD`          | (empty)      | Module subdirectory: `droplet`, `doks`, `k3s`, or `aws` |
| `ENV`          | `dev`        | Infisical environment                                   |
| `SECRETS_PATH` | `/terraform` | Infisical secrets path                                  |

**Examples:**

```bash
make init MOD=k3s       # first time for a module
make plan MOD=k3s       # preview
make apply MOD=k3s      # apply
make plan MOD=doks      # another module
make migrate MOD=k3s    # one-time local→R2 state copy
```

---

## Variables

Variables are defined per module in `infra/droplet/variables.tf`, `infra/doks/variables.tf`, `infra/k3s/variables.tf`, and `infra/aws/variables.tf`. Secrets are injected from Infisical (the `infisical run` wrapper in the Makefile) and mapped to Terraform input vars as `TF_VAR_*`. A `secrets.tfvars.example` template is kept for reference, but it is not the live secret source.

### `infra/droplet/variables.tf`

| Variable         | Type               | Required | Default         | Description                                               |
| ---------------- | ------------------ | -------- | --------------- | --------------------------------------------------------- |
| `DO_TOKEN`       | `string`           | ✓        | —               | DigitalOcean PAT (write scope)                            |
| `SSH_PUBLIC_KEY` | `string`           | ✓        | —               | Single SSH public key (flows via `TF_VAR_SSH_PUBLIC_KEY`) |
| `default_region` | `string`           | —        | `sgp1`          | Default region for all resources                          |
| `default_size`   | `string`           | —        | `s-1vcpu-1gb`   | Default Droplet size                                      |
| `default_image`  | `string`           | —        | `debian-13-x64` | Default Droplet image                                     |
| `servers`        | `map(object(...))` | —        | `{}`            | Server definitions — see [Droplets](#droplets)            |

### `infra/doks/variables.tf`

| Variable           | Type     | Required | Default | Description                               |
| ------------------ | -------- | -------- | ------- | ----------------------------------------- |
| `DO_TOKEN`         | `string` | ✓        | —       | DigitalOcean PAT (write scope)            |
| `default_region`   | `string` | —        | `sgp1`  | Default region for the cluster and DB     |
| `CLOUDFLARE_TOKEN` | `string` | ✓        | —       | Cloudflare Tunnel token for `cloudflared` |
| `GITHUB_USERNAME`  | `string` | ✓        | —       | GitHub username for PAT + GHCR auth       |
| `GITHUB_PAT`       | `string` | ✓        | —       | GitHub PAT (repo + read:packages scopes)  |
| `GITHUB_REPO_URL`  | `string` | ✓        | —       | GitOps repo URL (consumed by ArgoCD)      |
| `DIAGRAM_API_KEY`  | `string` | ✓        | —       | API key for the diagram service           |
| `app_yaml_path`    | `string` | —        | `null`  | Override path to ArgoCD Application YAML  |

### `infra/k3s/variables.tf`

| Variable            | Type     | Required | Default                                    | Description                               |
| ------------------- | -------- | -------- | ------------------------------------------ | ----------------------------------------- |
| `CLOUDFLARE_TOKEN`  | `string` | ✓        | —                                          | Cloudflare Tunnel token for `cloudflared` |
| `GITHUB_USERNAME`   | `string` | —        | `notseekeru`                               | GitHub username for GHCR auth             |
| `GITHUB_PAT`        | `string` | ✓        | —                                          | GitHub PAT (repo + read:packages scopes)  |
| `GITHUB_REPO_URL`   | `string` | —        | `https://github.com/notseekeru/gitops.git` | GitOps repo URL                           |
| `DIAGRAM_API_KEY`   | `string` | ✓        | —                                          | API key for the diagram service           |
| `POSTGRES_PASSWORD` | `string` | ✓        | —                                          | Password for the local PostgreSQL         |
| `app_yaml_path`     | `string` | —        | `null`                                     | Override path to ArgoCD Application YAML  |

### `infra/aws/variables.tf`

| Variable            | Type     | Required | Default          | Description                                                  |
| ------------------- | -------- | -------- | ---------------- | ------------------------------------------------------------ |
| `region`            | `string` | —        | `ap-southeast-1` | AWS region for all resources                                 |
| `vpc_cidr`          | `string` | —        | `10.0.0.0/16`    | CIDR block for the VPC                                       |
| `instance_type`     | `string` | —        | `t4g.micro`      | EC2 instance type (ARM/Graviton)                             |
| `db_instance_class` | `string` | —        | `db.t4g.micro`   | RDS instance class (Free Tier single-AZ)                     |
| `POSTGRES_PASSWORD` | `string` | ✓        | —                | RDS PostgreSQL admin password                                 |
| `ALERT_EMAIL`       | `string` | ✓        | —                | Email subscribed to SNS for budget + CloudWatch alerts        |

---

## Droplets

Add servers by setting the `servers` map variable (e.g. passed via `-var` for the droplet module, or populated into Infisical as `TF_VAR_servers`). Example:

```hcl
servers = {
  "vm-main-server" = {
    tags = ["main-server"]
  }
  "vm-worker-01" = {
    region = "nyc1"
    size   = "s-2vcpu-2gb"
    tags   = ["worker", "web"]
  }
  "vm-db-01" = {
    image  = "ubuntu-24-04-x64"
    size   = "s-2vcpu-4gb"
    tags   = ["database"]
  }
}
```

Each server key becomes the Droplet name. All fields are optional — missing values fall back to the defaults above. The `tags` field is augmented with the `"vm"` tag automatically.

Every Droplet is provisioned with the single `SSH_PUBLIC_KEY`. Droplets use `create_before_destroy` lifecycle for safe updates.

### Outputs

| Name          | Description                                                            |
| ------------- | ---------------------------------------------------------------------- |
| `droplets`    | Full map of all Droplets with IP, URN, region, size, image, tags, IPv6 |
| `droplet_ips` | Quick lookup: server name → public IPv4                                |

Retrieve after deploy:

```bash
terraform -chdir=infra/droplet output droplet_ips
```

---

## Ansible Integration

Post-apply, Terraform renders `infra/droplet/inventory.tmpl` → `~/ansible/inventories/droplets.ini`.

```ini
[all:vars]
ansible_user=root

[all]
vm-main-server ansible_host=203.0.113.1 region=sgp1 size=s-1vcpu-1gb image=debian-13-x64

[tag_main-server]
vm-main-server ansible_host=203.0.113.1
```

Servers are automatically grouped by tag (e.g. `[tag_web]`, `[tag_database]`), so you can target specific groups:

```bash
# All servers (from ~/ansible)
ansible-playbook -i inventories/droplets.ini playbooks/site.yml

# Only web workers
ansible-playbook -i inventories/droplets.ini --limit tag_web playbooks/site.yml
```

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

The `.envrc` already exports `KUBECONFIG=~/kubeconfig` on `cd` when direnv is active.

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

An AWS sandbox architecture (`infra/aws/`, state #4): VPC, public subnets, auto-scaling EC2 web
tier behind an Application Load Balancer, private single-AZ RDS PostgreSQL, and an S3 bucket
served via CloudFront. Provisioning targets a real AWS account; state still lives in R2.

### Credential split

Real AWS creds (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`) are distinct from the R2 state-backend pair (`TF_VAR_R2_*`). Collision ⇒ `InvalidAccessKeyId` — see [State Management](#state-management) and `docs/R2-backend-credential-conflict.md`.

### Credentials required

Requires Infisical secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (AWS account),

`TF_VAR_ALERT_EMAIL` (SNS alert email), and the `TF_VAR_R2_*` backend pair.

Web tier: EC2 instances in an Auto Scaling Group registered to an Application Load Balancer with
ELB health checks. Static assets: private S3 bucket served through CloudFront via Origin Access
Control (OAC). Alerting: a CloudWatch CPU alarm plus a zero-spend budget both publish to the SNS
topic (`TF_VAR_ALERT_EMAIL` must confirm the subscription once). See `AWS.md` for the full
architecture.

---

## ArgoCD

Installed via the `argoproj/argo-helm` chart at version `7.7.0` in the `argocd` namespace, alongside Kubernetes secrets and a root Application CR.

### Bootstrap flow

1. Terraform deploys Helm charts + secrets
2. Terraform applies the root Application manifest via the `kubectl` provider — this is the **only** manifest applied directly
3. That root Application tells ArgoCD to sync the rest from the GitOps repo

The manifest path defaults to `${path.module}/../../../gitops/app.yaml` (resolved at plan time) but can be overridden via `app_yaml_path`. See `infra/k3s/variables.tf` and `infra/doks/variables.tf`.

### CLI setup

```bash
# Retrieve initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d

# Port-forward the ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8443:443

# Login
argocd login localhost:8443 --grpc-web --insecure

# Change password
argocd account update-password --grpc-web
```

---

## Managed Database (PostgreSQL)

Database strategy varies by module: **DO Managed PG** for `doks` (see [DOKS Cluster](#doks-cluster-cloud)), **self-hosted StatefulSet** for `k3s` (see [K3s Module](#k3s-module-local)).
The connection string and API key are injected into the `diagram-secrets` Kubernetes secret consumed by application pods.

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

---

## Security

- **Secrets are managed in Infisical**, injected via `infisical run` — they never sit in a committed `.tfvars` file. The `secrets.tfvars.example` template is dummy/empty and safe to commit.
- The DO token is consumed via `var.DO_TOKEN` (marked `sensitive = true`).
- SSH keys are registered with Droplets at provision time — no post-provision injection.
- GitHub PAT and credentials are written directly to Kubernetes secrets — they never leave the Terraform state.
- R2 state-backend creds are namespaced `TF_VAR_R2_*` (+ `AWS_ENDPOINT_URL_S3`) and kept distinct from the real AWS provider creds (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`) to avoid the collision in `docs/R2-backend-credential-conflict.md`.
- `secrets.tfvars`, `*.tfvars`, `kubeconfig`, and `.infisical.json` are all in `.gitignore`.
- `secrets.tfvars.example` is safe to commit — it has dummy/empty values for all secrets.
- Consider GitLeaks + pre-commit hooks to prevent accidental secret commits.

---

## Cleanup

```bash
make destroy MOD=droplet
make destroy MOD=doks
make destroy MOD=k3s
```

Each module is destroyed independently.

---

## License

MIT. See [LICENSE](LICENSE).
