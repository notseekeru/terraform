# Diagram Postgres: Secret-vs-Role Credential Mismatch (2026-09-03)

## Problem

The prod diagram site appeared to lose all data: every `/api` call returned
`500`, the UI list/editor looked empty. Root cause was **no data loss and no
app regression** — the `diagram` Postgres role's stored SCRAM password no
longer equaled the `postgres123zxc` value baked by Terraform into
`diagram-secrets`, so the backend could not authenticate over TCP. All rows
stayed present throughout.

## Root Cause

Self-hosted Postgres (`postgres-0` StatefulSet, k3s, `database` namespace) with
`pg_hba.conf`:

```
local   all  all  all          trust
host    all  all  127.0.0.1/32 trust
host    all  all  all          scram-sha-256
```

Local/loopback connections bypass password checks (`trust`); every network/TCP
client (the backend, and any other host) is forced through `scram-sha-256`. A
days-prior password rotation updated the DB role OR the secret but **not both**,
so the role's stored SCRAM password no longer equaled
`postgres123zxc` in `diagram-secrets.database_url`.

Diagnosis was masked because on-box `psql -h localhost` succeeded via `trust`,
misleadingly confirming "the password is fine", while the real TCP path failed
with `password authentication failed for user "diagram"`.

## Why data loss was ruled out

- `public.diagrams` + `public.pgmigrations` present; `SELECT count(*)` → `3`.
- PG pod stable (`Running`), PVC `Bound`, data dir not re-initialized by the 11
  prior restarts.
- Backend deployment is stateless; no write path to the DB volume.

## Resolution

```sql
-- as superuser via the trust socket (here `diagram` is superuser)
ALTER USER diagram WITH PASSWORD 'postgres123zxc';
```

```bash
kubectl rollout restart deploy/diagram-backend
# verify over the exact TCP path clients use:
kubectl run pgtest --rm -i --restart=Never --image=postgres:16-alpine -- \
  psql "postgresql://diagram:postgres123zxc@postgres.database.svc.cluster.local:5432/diagramdb" -c "select 1"
# → 1
```

## Preventative Actions

1. **Rotate the exposed password.** `postgres123zxc` appeared in chat logs.
   Update BOTH Postgres and `diagram-secrets`, then restart backend.
2. **Single source of truth.** Store the DB password only in the k8s secret;
   derive the role password from it, never rotate independently.
3. **Post-rotation smoke test.** After any password change, connect as the app
   user over the Service DNS and `SELECT 1`, failing loudly on auth errors.
4. **Tighten `pg_hba.conf`.** Drop blanket `trust` for localhost; require
   `scram-sha-256` so on-box tests exercise the same path as real clients
   (prevents the misleading localhost pass).
5. **Reduce PVC data-loss exposure.** Postgres uses `local-path` PV with
   `Delete` reclaim on a single host. Pin `Retain`/NAS-backed storage and add
   scheduled backups / WAL archiving if history matters long-term.

### Labels

`type:incident` · `impact:data-access` · `cause:credential-mismatch` ·
`component:postgres` · `environment:homelab-k3s` · `resolved`
