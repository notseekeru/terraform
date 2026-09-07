#!/usr/bin/env sh
# Render the per-module R2 backend template into a gitignored .tfbackend file,
# substituting the R2 account id from the environment. Called by the Makefile
# backend targets under `infisical run`, so $TF_VAR_R2_ACCOUNT_ID is injected.
#
# Usage: render-tfbackend.sh <MOD> <template> <output>
#
# The committed *.tfbackend.tpl files hold only NON-secret backend config
# (bucket, key, region, endpoint shape, skip_*/use_lockfile flags). Secrets are
# still passed separately as `-backend-config="access_key=..."` flags from
# $$TF_VAR_R2_* in the Makefile — nothing secret is written here.

set -eu

MOD="$1"
TEMPLATE="$2"
OUT="$3"

if [ -z "${TF_VAR_R2_ACCOUNT_ID:-}" ]; then
  echo "render-tfbackend.sh: TF_VAR_R2_ACCOUNT_ID is not set (run under infisical run)" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
# Substitute the account id into the endpoint host. Use a safe delimiter (#)
# so the URL's slashes/colons don't break sed.
sed "s#__R2_ACCOUNT_ID__#${TF_VAR_R2_ACCOUNT_ID}#" "$TEMPLATE" > "$OUT"
echo "render-tfbackend.sh: wrote $OUT (backend for MOD=$MOD, key=terraform/${MOD}/terraform.tfstate)" >&2
