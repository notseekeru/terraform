# Postgres Role-Password Rotation Runbook (k3s module)

Rotation of the **`POSTGRES_PASSWORD`** for the self-hosted diagram Postgres must
go **through Terraform/Infisical only** — never a manual `ALTER USER` in the
pod. A manual `psql ... ALTER USER` (done 2026-09-03) changed the role's SCRAM
password without updating `diagram-secrets`, which broke the backend with
`password authentication failed for user "diagram"`. See
`docs/incident-2026-09-03-postgres-credential-mismatch.md`.

## Single source of truth

`infra/k3s/main.tf` derives **both** artifacts from one Terraform input:

- `var.POSTGRES_PASSWORD` → `postgres-credentials` secret → StatefulSet
  `POSTGRES_PASSWORD` env (initializes / owns the `diagram` role), **and**
- `var.POSTGRES_PASSWORD` → `diagram-secrets.database_url` (backend connection).

So a role password lives in exactly one place that Terraform writes. Keep it
that way. ArgoCD only *references* `diagram-secrets` by name (`secretKeyRef`),
it does not manage the secret content — nothing competes with Terraform.

## Rotation procedure

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
   - First snapshot the data (destructive workflow habit, cheap insurance):
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
6. Restart the backend so it reconnects with the fresh secret:
   ```bash
   kubectl rollout restart deploy/diagram-backend
   kubectl rollout status deploy/diagram-backend --timeout=60s
   kubectl logs deploy/diagram-backend --since=2m   # expect NO auth errors
   ```

## Do NOT

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

## Recovery rationale (keep localhost trust)

The module's Postgres uses the official image default that trusts local/loopback
(hidden behind `host all all all scram-sha-256` for TCP). This localhost `trust`
was the **only** recovery route when the app password broke — it let us reconnect
as superuser and realign the role. Tightening `pg_hba.conf` to require a password
on localhost would remove that safety valve unless a separate admin role and
recovery runbook are designed first. Pending such a design, leave the default in
place and treat any pg_hba hardening as a separate, deliberately-scoped change.

## Related

- Backup before destructive work: `make dump` (`Makefile`).
- Teardown: `make destroy MOD=k3s` (dump first).
