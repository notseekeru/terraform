# R2 State Backend vs AWS Provider: Credential Collision

## Problem

Terraform reported `InvalidAccessKeyId` on the AWS provider and/or backend
"value cannot be empty" on `init`, caused by two distinct credentials
colliding on the `AWS_ACCESS_KEY_ID` env var and the S3 backend `endpoint`
deprecation.

### Setup

* **State backend** = Cloudflare R2 (S3-compatible), bucket `terraform-state`.
* **Provisioning target** = real AWS account (`AKIA...` keys).
* Secrets live in **Infisical** (`dev`, path `/terraform`), injected unprefixed
  by `infisical run`.

### Root cause 1 — name collision

Infisical held **two** credential pairs:

| Secret | Held | Used by |
|---|---|---|
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | **R2** keys | s3 backend AND aws provider |
| `TF_VAR_AWS_ACCESS_KEY_ID` / `TF_VAR_AWS_SECRET_ACCESS_KEY` | **real AWS** | (shadowed, read by nothing) |

Both the `s3` backend and the `aws` provider read the **same** native
`AWS_ACCESS_KEY_ID` env var. With R2 creds in it, the provider failed
authentication (`InvalidAccessKeyId`). The `TF_VAR_*` prefix does **not**
decouple them — it only defines a Terraform input variable that nothing consumes.

### Root cause 2 — `infisical run` exec semantics

`infisical run -- <cmd>` **execs** `<cmd>` directly (no shell). A recipe prefix
like `AWS_ACCESS_KEY_ID=$R2... terraform ...` is treated as a literal executable
named `AWS_ACCESS_KEY_ID=...`:

```
exec: "AWS_ACCESS_KEY_ID=": executable file not found in $PATH
```

and a `-backend-config="bucket=$TF_VAR_R2_BUCKET"` is passed to the exec'd
program **verbatim** — the `$TF_VAR_R2_*` are expanded by make's own shell (empty)
or passed literally, never by a shell that has infisical's injected env.

### Root cause 3 — Terraform >= 1.5 rejects deprecated `endpoint`

Terraform 1.15 erroring on `-backend-config="endpoint=..."`:

```
Error: Invalid Value
The value cannot be empty or all whitespace
```

The S3 backend `endpoint` key is deprecated in favour of `endpoints.s3`, which
can be sourced from the env var `AWS_ENDPOINT_URL_S3`.

## Fix (applied)

1. **Rename Infisical secrets** so every credential namespace is unambiguous:

   | Secret | Now holds | Target |
   |---|---|---|
   | `AWS_ACCESS_KEY_ID` | real AWS key | aws provider |
   | `AWS_SECRET_ACCESS_KEY` | real AWS secret | aws provider |
   | `TF_VAR_R2_ACCESS_KEY_ID` | R2 key | s3 backend |
   | `TF_VAR_R2_SECRET_ACCESS_KEY` | R2 secret | s3 backend |
   | `TF_VAR_R2_ACCOUNT_ID` | R2 account id | endpoint |
   | `TF_VAR_R2_BUCKET` | `terraform-state` | bucket |
   | `AWS_ENDPOINT_URL_S3` | `https://<acct>.r2.cloudflarestorage.com` | endpoint |

2. **Makefile** (`Makefile`):
   * `backend_config` passes flat, non-deprecated keys only:
     `bucket`, `key`, `region`, `access_key`, `secret_key` (from `TF_VAR_R2_*`).
   * R2 URL injected via env `AWS_ENDPOINT_URL_S3` (modern `endpoints.s3` source),
     not the deprecated `endpoint` backend-config.
   * Backend-only targets (`init`, `upgradeinit`, `migrate`) exec terraform
     through `/bin/sh -c '...'` so the `$TF_VAR_R2_*` references expand from
     infisical's injected env.
   * `plan` / `apply` / `destroy` stay un-wrapped → provider reads native
     `AWS_ACCESS_KEY_ID` (real AWS). **No** R2 override leaks into them.

## Verification

```bash
make init MOD=aws   # backend bound to R2 bucket terraform-state
make plan MOD=aws   # provider authed with real AWS; "30 to add"
```

State object path in R2: `terraform/<module>/terraform.tfstate`.

Note: `infra/<module>/.terraform/terraform.tfstate` is a **local backend-cache
pointer** (version/backend only, no resources) — not state. Real state lives in
the R2 bucket.

## Guardrails (to avoid regression)

* Never store R2 creds under a bare `AWS_*` name in Infisical — keep them under
  `TF_VAR_R2_*`.
* Never put a `VAR=$other` prefix on an `infisical run --` command (no shell,
  direct exec). Wrap in `/bin/sh -c` if shell expansion is required.
* Use `AWS_ENDPOINT_URL_S3` (or `endpoints.s3` in HCL), not `endpoint`.
* Commits: `dd38d69`, `1dc43da`.

## Security note

The credential rename was performed by transcribing values previously dumped by
the CLI. **Rotate** `AWS_*`, `TF_VAR_R2_*`, and any Infisical token whose value
went through this process.
