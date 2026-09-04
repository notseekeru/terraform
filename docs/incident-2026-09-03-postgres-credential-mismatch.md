# Diagram Postgres: Secret-vs-Role Credential Mismatch (2026-09-03)

> Root-cause note for the diagram `/api` `500` / empty-UI episode. Auth failure,
> **no data loss and no app regression** — all rows stayed present throughout.
> Also contains the forward-looking **rotation runbook** (merged in 2026-09-04)

## Summary

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

## Why Data Loss Was Ruled Out

- `public.diagrams` + `public.pgmigrations` present; `SELECT count(*)` → `3`.
- PG pod stable (`Running`), PVC `Bound`, data dir not re-initialized by the 11
  prior restarts.
- Backend deployment is stateless; no write path to the DB volume.

## Resolution

```sql
-- as superuser via the trust socket (here `diagram` is superuser)
ALTER USER diagram WITH PASSWORD 'postgres123zxc';
```

## Verification

```bash
kubectl rollout restart deploy/diagram-backend
# verify over the exact TCP path clients use:
kubectl run pgtest --rm -i --restart=Never --image=postgres:16-alpine -- \
  psql "postgresql://diagram:postgres123zxc@postgres.database.svc.cluster.local:5432/diagramdb" -c "select 1"
# → 1
```

## Prevention

1. **Rotate the exposed password.** `postgres123zxc` appeared in chat logs.
   Update BOTH Postgres and `diagram-secrets` (the rotation runbook below is the
   safe way to do this), then restart backend.
2. **Single source of truth.** Store the DB password only in the k8s secret;
   drive both secret and role from one Terraform input. A manual `ALTER USER`
   outside Terraform is what caused this — see the runbook below.
3. **Post-rotation smoke test.** After any password change, verify over the
   Service DNS as the app user; fail loudly on auth errors.
4. **Tighten `pg_hba.conf`?** Deliberately **deferred** — the localhost `trust`
   is currently the only recovery safety valve. Requiring a password on
   localhost is fine only once a separate admin role + recovery runbook exist
   (see "Recovery rationale" below). Treat pg_hba hardening as its own
   separately-scoped change.
5. **Reduce PVC data-loss exposure.** Postgres uses `local-path` PV with
   `Delete` reclaim on a single host. Pin `Retain`/NAS-backed storage and add
   scheduled backups / WAL archiving if history matters long-term.

## Rotation Runbook

How to rotate `POSTGRES_PASSWORD` for the self-hosted diagram Postgres such that
the role and the secrets stay aligned.

Rotation must go **through Terraform/Infisical only** — never a manual
`ALTER USER` standing on its own (that desync is what caused this incident).

### Single source of truth

`infra/k3s/main.tf` derives **both** artifacts from one Terraform input:

- `var.POSTGRES_PASSWORD` → `postgres-credentials` secret → StatefulSet
  `POSTGRES_PASSWORD` env (initializes / owns the `diagram` role), **and**
- `var.POSTGRES_PASSWORD` → `diagram-secrets.database_url` (backend connection).

So a role password lives in exactly one place that Terraform writes. Keep it
that way. ArgoCD only *references* `diagram-secrets` by name (`secretKeyRef`),
it does not manage the secret content — nothing competes with Terraform.

### Procedure

1. **Change the value in Infisical**, not in Postgres:
   ```bash
   nix develop -c infisical secrets set POSTGRES_PASSWORD='<new-value>' \
     --env dev --path /terraform
   ```
   (Adjust `--env`/`--path` to your Infisical project/environment.)
2. **Preview** the drift (secrets + StatefulSet + `diagram-secrets` all update):
   ```bash
   make plan MOD=k3s
   ```
   Confirm only `POSTGRES_PASSWORD`-driven resources change.
3. **Apply**:
   - First snapshot the data (destructive-workflow habit, cheap insurance):
     ```bash
     make dump      # → ~/backups/diagramdb-<ts>.sql.gz
     ```
   - Then apply. This updates the **secrets** (`postgres-credentials`,
     `diagram-secrets`) to the new value. It does **not** touch the live role's
     SCRAM hash — initdb only ran at first boot, so on an existing cluster the
     `diagram` role keeps its current password until you set it.
     ```bash
     make apply MOD=k3s
     ```
4. **Realign the role to the same value** (the one legitimate manual step, done
   in lockstep with Terraform so both land on the new password — do **not** skip
   applying, or the secret and role drift again). Connect via the trust socket
   as superuser:
   ```bash
   kubectl exec -n database postgres-0 -- \
     psql -U diagram -d diagramdb \
     -c "ALTER USER diagram WITH PASSWORD '<the-new-infisical-value>';"
   ```
5. **Verify** over the exact TCP path clients use (fails loudly if misaligned):
   ```bash
   make verify-db-auth MOD=k3s
   # expected: authenticates over postgres.database.svc.cluster.local
   ```
6. **Restart the backend** so it reconnects with the fresh secret:
   ```bash
   kubectl rollout restart deploy/diagram-backend
   kubectl rollout status deploy/diagram-backend --timeout=60s
   kubectl logs deploy/diagram-backend --since=2m   # expect NO auth errors
   ```

### Do NOT

- Do **not** `kubectl exec <pg-pod> -- psql -U diagram -c "ALTER USER ..."` and
  stop there — that is what desynchronized role and secret in the first place.
- Do not rotate only one secret; both derive from `POSTGRES_PASSWORD`.
- If the role *and* secret are already out of sync, reset the role from inside
  via the trust socket as superuser **and then** re-apply Terraform so both are
  re-derived from the same value:
  ```bash
  kubectl exec -n database postgres-0 -- \
    psql -U diagram -d diagramdb \
    -c "ALTER USER diagram WITH PASSWORD 'pass-must-match-the-infisical-value';"
  make apply MOD=k3s   # re-derive diagram-secrets + postgres-credentials from the same value
  ```

### Recovery rationale (keep localhost trust for now)

The module's Postgres uses the official image default that trusts local/loopback
(hidden behind `host all all all scram-sha-256` for TCP). This localhost `trust`
was the **only** recovery route when the app password broke — it let us
reconnect as superuser and realign the role. Tightening `pg_hba.conf` to require
a password on localhost would remove that safety valve unless a separate admin
role and recovery runbook are designed first. Pending such a design, leave the
default in place and treat any pg_hba hardening as a separate,
deliberately-scoped change (Prevention item 4).

### Related

- Backup before destructive work: `make dump` (`Makefile`).
- Teardown: `make destroy MOD=k3s` (dump first).

## Labels

`type:incident` · `impact:data-access` · `cause:credential-mismatch` ·
`component:postgres` · `environment:homelab-k3s` · `resolved`
