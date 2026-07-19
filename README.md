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
- [Outputs](#outputs)
- [Ansible Integration](#ansible-integration)
- [Kubernetes Cluster](#kubernetes-cluster)
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
| **DigitalOcean Token** | Fine-grained PAT with write scope (`DO_TOKEN`) — see [Security](#security)               |
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

# 3. Initialize a module (droplet or kubernetes)
make init MOD=droplet

# 4. Preview
make plan MOD=droplet

# 5. Apply
make out MOD=droplet
make apply MOD=droplet

# Or for Kubernetes:
# make init MOD=kubernetes
# make plan MOD=kubernetes
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
│   └── kubernetes/          #   state #2 — DOKS + DB + helm + k8s resources
│       ├── versions.tf      #   Terraform & all providers (DO, helm, k8s, kubectl, local)
│       ├── provider.tf      #   DO + dynamic k8s/helm/kubectl providers
│       ├── variables.tf     #   DO_TOKEN, CLOUDFLARE_TOKEN, GITHUB_*, DIAGRAM_API_KEY
│       └── main.tf          #   cluster → DB → helm releases → secrets → argocd app
├── secrets.tfvars           # Sensitive variables (gitignored)
├── secrets.tfvars.example   # Template for secrets
├── Makefile                 # Workflow shortcuts (accepts MOD=, ENV=, SECRETS_PATH=)
├── flake.nix                # Nix dev shell definition
├── .envrc                   # direnv: auto-nix + KUBECONFIG
```

---

## Makefile Workflow

All targets accept `MOD=droplet` or `MOD=kubernetes`. The `infra/` prefix is baked into each target.

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
| `make infisical-plan`  | `infisical run --path $(SECRETS_PATH) --env $(ENV) -- terraform -chdir=infra/$(MOD) plan`  | Plan via Infisical secrets     |
| `make infisical-apply` | `infisical run --path $(SECRETS_PATH) --env $(ENV) -- terraform -chdir=infra/$(MOD) apply` | Apply via Infisical secrets    |

**Variables:**

| Variable       | Default      | Description                                    |
| -------------- | ------------ | ---------------------------------------------- |
| `MOD`          | (empty)      | Module subdirectory: `droplet` or `kubernetes` |
| `ENV`          | `dev`        | Infisical environment                          |
| `SECRETS_PATH` | `/terraform` | Infisical secrets path                         |

**Examples:**

```bash
make plan                          # plan droplet changes (default module)
make plan MOD=kubernetes           # plan kubernetes changes
make apply MOD=kubernetes          # apply kubernetes
make infisical-plan MOD=kubernetes # plan using Infisical
```

---

## Variables

Variables are defined per module in `infra/droplet/variables.tf` and `infra/kubernetes/variables.tf`. Secrets live in `secrets.tfvars` (gitignored).

### `infra/droplet/variables.tf`

| Variable          | Type               | Required | Default         | Description                                    |
| ----------------- | ------------------ | -------- | --------------- | ---------------------------------------------- |
| `DO_TOKEN`        | `string`           | ✓        | —               | DigitalOcean PAT (write scope)                 |
| `ssh_public_keys` | `map(string)`      | ✓        | —               | SSH key name → public key material             |
| `default_region`  | `string`           | —        | `sgp1`          | Default region for all resources               |
| `default_size`    | `string`           | —        | `s-1vcpu-1gb`   | Default Droplet size                           |
| `default_image`   | `string`           | —        | `debian-13-x64` | Default Droplet image                          |
| `servers`         | `map(object(...))` | —        | `{}`            | Server definitions — see [Droplets](#droplets) |

### `infra/kubernetes/variables.tf`

| Variable           | Type     | Required | Default | Description                               |
| ------------------ | -------- | -------- | ------- | ----------------------------------------- |
| `DO_TOKEN`         | `string` | ✓        | —       | DigitalOcean PAT (write scope)            |
| `default_region`   | `string` | —        | `sgp1`  | Default region for the cluster and DB     |
| `CLOUDFLARE_TOKEN` | `string` | ✓        | —       | Cloudflare Tunnel token for `cloudflared` |
| `GITHUB_USERNAME`  | `string` | ✓        | —       | GitHub username for PAT + GHCR auth       |
| `GITHUB_PAT`       | `string` | ✓        | —       | GitHub PAT (repo + read:packages scopes)  |
| `GITHUB_REPO_URL`  | `string` | ✓        | —       | GitOps repo URL (consumed by ArgoCD)      |
| `DIAGRAM_API_KEY`  | `string` | ✓        | —       | API key for the diagram service           |

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

---

## Outputs for Droplets

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

Post-apply, Terraform renders `infra/droplet/inventory.tmpl` → `~/ansible/inventories/droplets.ini` (sibling directory, referenced via `../../../ansible/` from the module).

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

## Kubernetes Cluster

| Attribute     | Value                | Notes                        |
| ------------- | -------------------- | ---------------------------- |
| **Name**      | `lab-cluster`        | Singleton — one cluster only |
| **Region**    | `var.default_region` | Inherits `sgp1` default      |
| **Version**   | `1.34.8-do.2`        | DO-managed Kubernetes        |
| **Node pool** | 3 × `s-2vcpu-2gb`    | Worker-pool, 6 GB total      |

### Usage

The kubeconfig is written to `~/kubeconfig` at apply time. The `.envrc` sets `KUBECONFIG` automatically if direnv is configured:

```bash
# Temporary (current shell)
export KUBECONFIG=~/kubeconfig
kubectl get nodes

# Or use direnv (persistent per directory)
echo 'export KUBECONFIG=$(pwd)/kubeconfig' >> .envrc && direnv allow
# ^ Already set in the repo's .envrc for the flake path
```

---

## Nginx Ingress Controller

Installed via Helm in the `ingress-nginx` namespace. The service is configured as `ClusterIP` (internal only) — Cloudflare Tunnel routes external traffic to it.

| Setting        | Value           |
| -------------- | --------------- |
| Namespace      | `ingress-nginx` |
| Service type   | `ClusterIP`     |
| Request memory | `128Mi`         |
| Request CPU    | `100m`          |

---

## ArgoCD

Installed via the `argoproj/argo-helm` chart at version `7.7.0` in the `argocd` namespace, alongside the necessary Kubernetes secrets and a root Application CR.

### Bootstrap flow

1. Terraform deploys the cluster + Helm chart + secrets
2. Terraform applies the root Application manifest via the `kubectl` provider — this is the **only** manifest applied directly
3. That root Application tells ArgoCD to sync the rest from the GitOps repo

The manifest path defaults to `gitops/app.yaml` (relative to the Terraform root) but can be overridden via the `app_yaml_path` variable. See `infra/kubernetes/variables.tf`.

**Note:** The default `gitops/app.yaml` doesn't exist yet — create this file or a stub, or set `app_yaml_path` to an existing path.

### CLI setup

```bash
# Temporary (current shell) — already handled by .envrc
export KUBECONFIG=~/kubeconfig

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

A DigitalOcean managed PostgreSQL database (`diagram-db`) is provisioned in the same VPC as the Kubernetes cluster for low-latency private connectivity.

| Setting    | Value                 |
| ---------- | --------------------- |
| Engine     | PostgreSQL 16         |
| Size       | `db-s-1vcpu-1gb`      |
| Node count | 1                     |
| Region     | `var.default_region`  |
| Network    | Cluster VPC (private) |

The database user credentials and connection string are injected into Kubernetes as the `diagram-secrets` secret — consumed by application pods.

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

- **`secrets.tfvars`** contains your `DO_TOKEN`, Cloudflare token, GitHub PAT, and API keys — **never commit** this file.
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
make destroy MOD=kubernetes
```

Each module is destroyed independently. The kubernetes `destroy` will tear down the cluster, database, and all associated resources.

---

## License

MIT. See [LICENSE](LICENSE).
