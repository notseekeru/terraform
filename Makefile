MOD ?=
ENV ?= dev
SECRETS_PATH ?= /terraform

# R2 backend config — bucket/key come from Infisical, per-module state key.
# Infisical keys: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, R2_ACCOUNT_ID, R2_BUCKET.
# Endpoint is derived from R2_ACCOUNT_ID.
backend_config = -backend-config="bucket=$$R2_BUCKET" \
	-backend-config="key=terraform/$(MOD)/terraform.tfstate" \
	-backend-config="endpoint=https://$$R2_ACCOUNT_ID.r2.cloudflarestorage.com" \
	-backend-config="region=auto"

.PHONY: init upgradeinit plan out apply destroy fmt validate \
	infi-init infi-upgradeinit infi-plan infi-out infi-apply infi-destroy \
	migrate dump

fmt:
	terraform -chdir=infra/$(MOD) fmt

validate:
	terraform -chdir=infra/$(MOD) validate

# Backend init requires Infisical env (R2 creds). Plain targets route here.
init: infi-init
upgradeinit: infi-upgradeinit

plan:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) plan

out:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) plan -out=tfplan

apply:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) apply

destroy:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) destroy

infi-init:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) init $(backend_config)

infi-upgradeinit:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) init -upgrade $(backend_config)

infi-plan:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) plan

infi-out:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) plan -out=tfplan

infi-apply:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) apply

infi-destroy:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) destroy

# One-time: push local state to R2 (run per module, e.g. make migrate MOD=k3s)
migrate:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) init -migrate-state $(backend_config)

# Dump the diagramdb from the local k3s postgres to ~/backups
dump:
	@mkdir -p ~/backups
	@kubectl exec -n database svc/postgres -- pg_dump -U diagram -d diagramdb \
		| gzip > ~/backups/diagramdb-$$(date +%F-%H%M).sql.gz
	@echo "Backup saved: ~/backups/diagramdb-$$(date +%F-%H%M).sql.gz"
