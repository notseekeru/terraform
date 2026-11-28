# ADR 0005: Postgres state backend on Neon

- **Status:** Accepted
- **Date:** 2026-11-28
- **Supersedes:** ADR 0001 (R2 endpoint delivery through the `s3` backend)
- **Related:** `Makefile`, `infra/<MOD>/versions.tf`, `README.md`

## Context

ADR 0001 delivered R2 as the state store through the `s3` backend. That backend shares
the AWS SDK environment namespace with the `aws` provider, which was the original
collision, and it needed a pin plus a stored address to keep the two apart. The flags
that delivered the address also forced a shell wrapper, because the secrets runner
execs command text without expanding it.

HCP Terraform was the first choice for a standard free backend and is unavailable. The
account cannot create a free organization, and the counter behind that limit does not
reset.

## Decision

State lives in Postgres (Neon) through the `pg` backend, one schema per module.

1. `backend "pg" {}` with no attributes in each module. `PG_CONN_STR` and
   `PG_SCHEMA_NAME` arrive from the environment that infisical injects, and the
   Makefile exports the schema name from `MOD`.
2. No `-backend-config` flags and no `/bin/sh -c` wrapper on any target.
3. The connection string uses the direct endpoint, not the pooler, and carries
   `options=endpoint%3D<endpoint-id>`, which Neon requires for clients that lack SNI.
4. Locking is Postgres advisory locks. `force-unlock` is not supported.

## Consequences

- Removes three backend flags, the shell wrapper, and the R2 credentials from the
  credential path. One secret, `PG_CONN_STR`, replaces all of it.
- Durability is weaker than object versioning. State is a row covered by Neon's
  point-in-time window, not an immutable object per revision. Accepted at this scale.
- State and the app now share one vendor, so a Neon outage blocks the fix as well as
  the app. The alternative, TFC, is blocked and the S3 options either bill or collide.
- Advisory locks are session-scoped. A hung run holds its lock until the connection
  drops, and there is no CLI unlock; terminating the session is the remedy.

## Migration

`make migrate MOD=<m>` runs `init -migrate-state`, which copies from the previously
configured `s3` backend. It asks for confirmation, so it needs `yes` piped in when run
non-interactively. Verify with `PG_SCHEMA_NAME=tf_<m> terraform -chdir=infra/<m> state list`
and a plan before deleting the old bucket objects.
