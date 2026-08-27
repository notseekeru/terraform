MOD ?=
ENV ?= dev
SECRETS_PATH ?= /terraform

# Infisical injects these unprefixed (AWS_* for the s3 backend, R2_* for the
# state bucket). Endpoint is derived from the R2 account id.
backend_config = -backend-config="bucket=$$R2_BUCKET" \
	-backend-config="key=terraform/$(MOD)/terraform.tfstate" \
	-backend-config="endpoint=https://$$R2_ACCOUNT_ID.r2.cloudflarestorage.com" \
	-backend-config="region=auto"

.PHONY: fmt validate init upgradeinit plan apply destroy migrate dump secrets

fmt:
	terraform -chdir=infra/$(MOD) fmt

validate:
	terraform -chdir=infra/$(MOD) validate

init:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) init $(backend_config)

upgradeinit:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) init -upgrade $(backend_config)

plan:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) plan

apply:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) apply

destroy:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) destroy

# One-time (per module): push local state to R2. Only needed on first backend setup.
migrate:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) init -migrate-state $(backend_config)

# Dump diagramdb from local k3s postgres to ~/backups

dump:
	@mkdir -p ~/backups
	@kubectl exec -n database svc/postgres -- pg_dump -U diagram -d diagramdb \
		| gzip > ~/backups/diagramdb-$$(date +%F-%H%M).sql.gz
	@echo "Backup saved: ~/backups/diagramdb-$$(date +%F-%H%M).sql.gz"

secrets:
	infisical secrets generate-example-env --env=dev --path=/terraform
