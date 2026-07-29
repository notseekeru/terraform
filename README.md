# Terraform — Personal Cloud Infrastructure

> Infrastructure-as-Code for my personal cloud environment.  
> **Provider:** DigitalOcean · **Provisioner:** Terraform · **Orchestrator:** ArgoCD

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quickstart](#quickstart)
- [Project Layout](#project-layout)
- [Makefile Workflow](#makefile-workflow)
- [Variables](#variables)
- [Droplets](#droplets)
- [Ansible Integration](#ansible-integration)
- [DOKS Cluster (Cloud)](#doks-cluster-cloud)
- [K3s Module (Local)](#k3s-module-local)
- [Nginx Ingress Controller](#nginx-ingress-controller)
- [ArgoCD](#argocd)
- [Managed Database (PostgreSQL)](#managed-database-postgresql)
- [Kubernetes Secrets](#kubernetes-secrets)
- [Nix Dev Shell](#nix-dev-shell)
- [Security](#security)
- [Cleanup](#cleanup)

---

## Prerequisites

| Requirement            | Details                                                                                  |
| ---------------------- | ---------------------------------------------------------------------------------------- |
| **Terraform**          | `>= 1.0` ([install guide](https://developer.hashicorp.com/terraform/install))            |
| **DigitalOcean Token** | Fine-grained PAT with write scope (`DO_TOKEN`) — needed only for `doks` / `droplet`     |
| **SSH Keys**           | Public keys uploaded to your DO account or provided inline via `secrets.tfvars`          |
| **Make**               | (Optional) `make` for the workflow targets below                                         |
| **Nix**                | (Optional) `nix develop` for an isolated dev shell — see [Nix Dev Shell](#nix-dev-shell) |
| **direnv**             | (Optional) Auto-loads the Nix shell and `KUBECONFIG` on `cd`                             |

---

## Quickstart

```bash
# 1. Clone & enter
cd terraform

# 2. Copy and populate secrets
cp secrets.tfvars.example secrets.tfvars
# Edit secrets.tfvars — add your DO_TOKEN, SSH public key(s), and other secrets

# 3. Initialize a module (droplet, doks, or k3s)
make init MOD=droplet

# 4. Preview
make plan MOD=droplet

# 5. Apply
make out MOD=droplet
make apply MOD=droplet

# For DOKS:
# make init MOD=doks
# make plan MOD=doks

# For local k3s:
# make init MOD=k3s
# make plan MOD=k3s
```

---

## Project Layout

```
terraform/
├── infra/                   # Terraform root modules
│   ├── droplet/             #   state #1 — standalone DO droplets
│   │   ├── versions.tf      #   Terraform & DO + local providers
│   │   ├── provider.tf      #   DigitalOcean provider
│   │   ├── variables.tf     #   DO_TOKEN, ssh_keys, servers, region defaults
│   │   ├── main.tf          #   SSH keys, droplets, Ansible inventory
│   │   ├── inventory.tmpl   #   Ansible inventory template (rendered post-apply)
│   │   └── outputs.tf       #   droplet IPs and attributes
│   ├── doks/                #   state #2 — DOKS cluster (cloud)
│   │   ├── versions.tf      #   DO, helm, k8s, kubectl, local
│   │   ├── provider.tf      #   DO + dynamic k8s/helm/kubectl providers
│   │   ├── variables.tf     #   DO_TOKEN, CLOUDFLARE_TOKEN, GITHUB_*, DIAGRAM_API_KEY
│   │   └── main.tf          #   cluster → managed PG → helm releases → secrets → argocd app
│   └── k3s/                 #   state #3 — local k3s cluster (no DO)
│       ├── versions.tf      #   helm, k8s, kubectl only
│       ├── provider.tf      #   providers read from ~/.kube/config
│       ├── variables.tf     #   CLOUDFLARE_TOKEN, GITHUB_*, DIAGRAM_API_KEY, POSTGRES_PASSWORD
│       └── main.tf          #   helm releases → self-hosted PG StatefulSet → secrets → argocd app
├── secrets.tfvars           # Sensitive variables (gitignored)
├── secrets.tfvars.example   # Template for secrets
├── Makefile                 # Workflow shortcuts (accepts MOD=, ENV=, SECRETS_PATH=)
├── flake.nix                # Nix dev shell definition
├── .envrc                   # direnv: auto-nix + KUBECONFIG
```

---

## Makefile Workflow

All targets accept `MOD=droplet`, `MOD=doks`, or `MOD=k3s`. The `infra/` prefix is baked into each target.

| Target                 | Command                                                                                    | Description                    |
| ---------------------- | ------------------------------------------------------------------------------------------ | ------------------------------ |
| `make init`            | `terraform -chdir=infra/$(MOD) init`                                                       | Initialize providers & backend |
| `make upgradeinit`     | `terraform -chdir=infra/$(MOD) init -upgrade`                                              | Upgrade initialization         |
| `make plan`            | `terraform -chdir=infra/$(MOD) plan -var-file=../../secrets.tfvars`                        | Preview changes                |
| `make out`             | `terraform -chdir=infra/$(MOD) plan -var-file=../../secrets.tfvars -out=tfplan`            | Save plan to binary file       |
| `make apply`           | `terraform -chdir=infra/$(MOD) apply tfplan`                                               | Apply saved plan               |
| `make destroy`         | `terraform -chdir=infra/$(MOD) destroy -var-file=../../secrets.tfvars`                     | Tear down resources            |
| `make fmt`             | `terraform -chdir=infra/$(MOD) fmt`                                                        | Format all `.tf` files         |
| `make validate`        | `terraform -chdir=infra/$(MOD) validate`                                                   | Validate configuration         |
| `make infi-plan`       | `infisical run --path $(SECRETS_PATH) --env $(ENV) -- terraform -chdir=infra/$(MOD) plan`  | Plan via Infisical secrets     |
| `make infi-out`        | `infisical run --path $(SECRETS_PATH) --env $(ENV) -- terraform -chdir=infra/$(MOD) plan -out=tfplan` | Plan + save via Infisical |
| `make infi-apply`      | `infisical run --path $(SECRETS_PATH) --env $(ENV) -- terraform -chdir=infra/$(MOD) apply` | Apply via Infisical secrets    |
| `make infi-destroy`    | `infisical run --path $(SECRETS_PATH) --env $(ENV) -- terraform -chdir=infra/$(MOD) destroy` | Destroy via Infisical         |

**Variables:**

| Variable       | Default      | Description                                        |
| -------------- | ------------ | -------------------------------------------------- |
| `MOD`          | (empty)      | Module subdirectory: `droplet`, `doks`, or `k3s`   |
| `ENV`          | `dev`        | Infisical environment                              |
| `SECRETS_PATH` | `/terraform` | Infisical secrets path                             |

**Examples:**

```bash
make plan                          # plan droplet changes (default module)
make plan MOD=doks                 # plan DOKS changes
make plan MOD=k3s                  # plan k3s changes
make apply MOD=k3s                 # apply k3s
make infi-plan MOD=doks            # plan using Infisical
```

---

## Variables

Variables are defined per module in `infra/droplet/variables.tf`, `infra/doks/variables.tf`, and `infra/k3s/variables.tf`. Secrets live in `secrets.tfvars` (gitignored).

### `infra/droplet/variables.tf`

| Variable          | Type               | Required | Default         | Description                                    |
| ----------------- | ------------------ | -------- | --------------- | ---------------------------------------------- |
| `DO_TOKEN`        | `string`           | ✓        | —               | DigitalOcean PAT (write scope)                 |
| `ssh_public_keys` | `map(string)`      | ✓        | —               | SSH key name → public key material             |
| `default_region`  | `string`           | —        | `sgp1`          | Default region for all resources               |
| `default_size`    | `string`           | —        | `s-1vcpu-1gb`   | Default Droplet size                           |
| `default_image`   | `string`           | —        | `debian-13-x64` | Default Droplet image                          |
| `servers`         | `map(object(...))` | —        | `{}`            | Server definitions — see [Droplets](#droplets) |

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

### `infra/k3s/variables.tf`

| Variable           | Type     | Required | Default                                    | Description                               |
| ------------------ | -------- | -------- | ------------------------------------------ | ----------------------------------------- |
| `CLOUDFLARE_TOKEN` | `string` | ✓        | —                                          | Cloudflare Tunnel token for `cloudflared` |
| `GITHUB_USERNAME`  | `string` | —        | `notseekeru`                               | GitHub username for GHCR auth             |
| `GITHUB_PAT`       | `string` | ✓        | —                                          | GitHub PAT (repo + read:packages scopes)  |
| `GITHUB_REPO_URL`  | `string` | —        | `https://github.com/notseekeru/gitops.git` | GitOps repo URL                           |
| `DIAGRAM_API_KEY`  | `string` | ✓        | —                                          | API key for the diagram service           |
| `POSTGRES_PASSWORD`| `string` | ✓        | —                                          | Password for the local PostgreSQL         |
| `app_yaml_path`    | `string` | —        | `../../../gitops/app.yaml`                 | Path to root ArgoCD Application manifest  |

---

## Droplets

Add servers by extending the `servers` map in `secrets.tfvars`:

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

Every Droplet is provisioned with all SSH keys from `ssh_public_keys`. Droplets use `create_before_destroy` lifecycle for safe updates.

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

A DigitalOcean managed PostgreSQL 16 (`db-s-1vcpu-1gb`) is provisioned in the same VPC as the cluster. Credentials injected into `diagram-secrets`.

---

## K3s Module (Local)

For local development or edge deployments. Runs against an existing k3s cluster — reads `~/.kube/config` directly.

| Aspect | Detail |
| ------ | ------ |
| **No DO dependency** | All providers point at local kubeconfig |
| **Database** | Self-hosted PostgreSQL 16 StatefulSet in `database` namespace, 5Gi PVC on `local-path` storage class |
| **Connection string** | `postgresql://diagram:${pass}@postgres.database.svc.cluster.local:5432/diagramdb` |

### Init & Apply

```bash
make init MOD=k3s
make plan MOD=k3s   # uses secrets.tfvars
make out MOD=k3s
make apply MOD=k3s
```

Requires `POSTGRES_PASSWORD` in `secrets.tfvars`.

---

## Nginx Ingress Controller

Installed via Helm in both `doks` and `k3s` modules, in the `ingress-nginx` namespace. Configured as `ClusterIP` — Cloudflare Tunnel handles external routing.

| Setting        | Value           |
| -------------- | --------------- |
| Namespace      | `ingress-nginx` |
| Service type   | `ClusterIP`     |
| Request memory | `128Mi`         |
| Request CPU    | `100m`          |

---

## ArgoCD

Installed via the `argoproj/argo-helm` chart at version `7.7.0` in the `argocd` namespace, alongside Kubernetes secrets and a root Application CR.

### Bootstrap flow

1. Terraform deploys Helm charts + secrets
2. Terraform applies the root Application manifest via the `kubectl` provider — this is the **only** manifest applied directly
3. That root Application tells ArgoCD to sync the rest from the GitOps repo

The manifest path defaults to `../../../gitops/app.yaml` (relative to the module) but can be overridden via `app_yaml_path`. See `infra/k3s/variables.tf` and `infra/doks/variables.tf`.

**Note:** The default `gitops/app.yaml` doesn't exist yet — create a stub or set `app_yaml_path` to an existing path.

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

Two deployment strategies depending on the module:

| Module  | Database type     | Details                                                         |
| ------- | ----------------- | --------------------------------------------------------------- |
| `doks`  | DO Managed PG     | `db-s-1vcpu-1gb`, PostgreSQL 16, same VPC, private connectivity |
| `k3s`   | Self-hosted PG    | StatefulSet `postgres:16-alpine`, 5Gi PVC, `database` namespace |

The connection string and API key are injected into the `diagram-secrets` Kubernetes secret consumed by application pods.

---

## Kubernetes Secrets

The following secrets are created automatically by Terraform (no manual `kubectl create secret` needed):

| Secret Name         | Namespace | Purpose                                      |
| ------------------- | --------- | -------------------------------------------- |
| `cloudflared-token` | `default` | Cloudflare Tunnel token for `cloudflared`    |
| `ghcr-login`        | `default` | Docker registry credentials for GHCR         |
| `diagram-secrets`   | `default` | API key + PostgreSQL connection string       |
| `repo-secret`       | `argocd`  | ArgoCD repository credentials (private repo) |

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

- **`secrets.tfvars`** contains your tokens, PATs, and API keys — **never commit** this file.
- The DO token is consumed via `var.DO_TOKEN` (marked `sensitive = true`).
- SSH keys are registered with Droplets at provision time — no post-provision injection.
- GitHub PAT and credentials are written directly to Kubernetes secrets — they never leave the Terraform state.
- `secrets.tfvars`, `*.tfvars`, and `kubeconfig` are all in `.gitignore`.
- Consider using a vault or environment variables instead of plain-text `.tfvars` for production setups.
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
