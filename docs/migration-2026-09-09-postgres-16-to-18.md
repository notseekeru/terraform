# Postgres 16 → 18 Migration (2026-09-09)

> Directed migration of the self-hosted diagram Postgres (`database` ns, k3s,
> `postgres-0` StatefulSet) from `postgres:16-alpine` to `postgres:18-alpine`.
> Strategy: **logical dump → fresh PG18 initdb → dump restore**.
> Result: data intact, app reconnected, no crash-loop. This doc is the runbook +
> the record of the one production blocker hit and its fix.

## Summary

Postgres was bumped to 18 by Renovate (`98c096b`, image `postgres:18-alpine`)
but never applied. Applying it against the existing PG16 data dir fails by
design: **PG16 files are not readable by PG18**. Additionally the **PG18+
Docker image changed its storage layout** (docker-library/postgres#1259) and
refuses to boot when a volume is mounted flat at `/var/lib/postgresql/data`.
Both had to be addressed. Migration completed with data intact.

## Pre-migration facts (verified)

- PG: `postgres:16-alpine` (16.14), STS `postgres`, ns `database`, 1 replica.
- Volume: PVC `data-postgres-0`, 5Gi, class **local-path**, reclaim **Delete**,
  host `piserver`, PV uid `0eb7dbce-…`, old data at PVC `pgdata/` (mounted via
  `subPath: pgdata` to `/var/lib/postgresql/data`).
- DB: `diagramdb`, role `diagram`, **base install** (no contrib/optional ext),
  ~7.7MB (`diagrams`=3, `pgmigrations`=1).
- Consumers: `diagram-backend`/`-frontend` in ns `default`, connect to
  `postgres.database.svc.cluster.local:5432/diagramdb` (Service unchanged).
- Secrets `postgres-credentials` + `diagram-secrets.database_url` derive from one
  Terraform input (`var.POSTGRES_PASSWORD`), names/wiring unchanged.
- Repo state: local was 4 behind origin; `origin/main` already carried the
  `postgres:18-alpine` bump.

## Runbook (as executed)

### 1. Sync + backup
```bash
cd ~/terraform
git pull origin main          # fast-forward 5e471d8 → 55ea58c (brings 18-bump)
make dump MOD=k3s             # → ~/backups/diagramdb-<ts>.sql.gz
gzip -t ~/backups/diagramdb-<ts>.sql.gz   # integrity check
# NOTE: ~/backups and the local-path PVC are same host — off-host copy advised.
```

### 2. Freeze writes (app scale-down)
```bash
kubectl -n default scale deploy diagram-backend --replicas=0   # writer quiesced
kubectl -n default rollout status deploy/diagram-backend
```

### 3. Plan + confirm no data-plane destroy
```bash
make plan MOD=k3s   # expect: 0 destroyed; STS image 16→18 in-place. PVC untouched.
```

### 4. Stop PG16, empty old data dir so PG18 can init fresh
```bash
kubectl -n database scale sts postgres --replicas=0
kubectl -n database rollout status sts/postgres
# Empty PVC pgdata subtree via scratch pod (DO NOT delete the PVC — Delete reclaim):
#   mount data-postgres-0 at /volume, then:
#   find /volume/pgdata -mindepth 1 -delete
```

### 5. Apply (image=18) → hit the PG18 flat-mount boot blocker
```bash
infisical run --path /terraform --env dev -- \
  terraform -chdir=infra/k3s apply -auto-approve
```
PG18 pod **CrashLoopBackOff** with: `"in 18+, these images store data in a
pg_ctlcluster-compatible layout … appears to be PostgreSQL data in
/var/lib/postgresql/data (unused mount/volume)"` — see docker-library/postgres#1259.

### 6. Fix the StatefulSet volume mount (the real fix)
PG18+ wants the volume mounted at **`/var/lib/postgresql`** (parent) so the
entrypoint initdb's into a versioned subdir; a flat mount at
`/var/lib/postgresql/data` is rejected.
```hcl
# infra/k3s/main.tf — kubernetes_stateful_set_v1.postgres template
volume_mount {
  name       = "data"
  mount_path = "/var/lib/postgresql"   # was "/var/lib/postgresql/data" + sub_path "pgdata"
}
```
Re-apply 0-destroy plan; pod comes up on PG18 with
`PGDATA=/var/lib/postgresql/18/docker`.

### 7. Restore dump
```bash
gunzip -c ~/backups/diagramdb-<ts>.sql.gz | \
  kubectl -n database exec -i postgres-0 -- psql -U diagram -d diagramdb
```

### 8. Verify + reconnect app
```bash
# row counts, ownership
kubectl -n database exec postgres-0 -- psql -U diagram -d diagramdb \
  -c "SELECT count(*) FROM public.diagrams;"   # 3
kubectl -n default scale deploy diagram-backend --replicas=1
kubectl -n default rollout status deploy/diagram-backend
psql -U diagram -d diagramdb -c \
  "SELECT usename,count(*) FROM pg_stat_activity WHERE usename='diagram' GROUP BY 1;"  # ≥1 live conn
```

## Result (verified)

- `postgres-0` Running 1/1, 0 restarts, **PostgreSQL 18.6**.
- `diagrams`=3, `pgmigrations`=1, owner `diagram`, `PGDATA=/var/lib/postgresql/18/docker`.
- `diagram-backend` 1/1 with live `diagram` TCP connections; no auth errors.
- PVC `data-postgres-0` still `Bound` to original PV (uid unchanged) — **no PVC rebuild**.
- Working tree change: single `infra/k3s/main.tf` mount fix (image bump was upstream).

## Notes / gotchas

- **PG18 layout change is here to stay** and is the correct future path
  (`pg_upgrade --link` without mount-boundary issues) — do **not** revert the
  mount to `/var/lib/postgresql/data` for future 18→20 upgrades.
- Mid-run an orphaned remote-state lock appeared (apply client killed while
  apply had completed). Cleared with
  `terraform -chdir=infra/k3s force-unlock -force <lock-id>`. After any
  interrupted `make apply`, check state lock before re-planning.
- Probes/dumps in `Makefile` still reference `postgres:16-alpine` as the
  **client** image (e.g. `verify-db-auth`). Harmless (client only) but stale;
  consider bumping to `18-alpine`.
- Recovery if PVC ever lost: re-init via step 4–7 from the verified dump. Same
  host for PVC + backups remains the single-disaster risk.

## Labels

`type:migration` · `impact:data-plane` · `cause:major-version-upgrade` ·
`component:postgres` · `environment:homelab-k3s` · `result:success`
