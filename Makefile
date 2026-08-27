MOD ?=
ENV ?= dev
SECRETS_PATH ?= /terraform

# R2 state-bucket creds are namespaced TF_VAR_R2_* so they never collide with the
# AWS provider's native AWS_ACCESS_KEY_ID. backend_config reaches R2 via those.
# Endpoint is derived from the R2 account id.
backend_config = -backend-config="bucket=$$TF_VAR_R2_BUCKET" \
	-backend-config="key=terraform/$(MOD)/terraform.tfstate" \
	-backend-config="endpoint=https://$$TF_VAR_R2_ACCOUNT_ID.r2.cloudflarestorage.com" \
	-backend-config="region=auto"

.PHONY: fmt validate init upgradeinit plan apply destroy migrate dump secrets

fmt:
	terraform -chdir=infra/$(MOD) fmt

validate:
	terraform -chdir=infra/$(MOD) validate

init:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		AWS_ACCESS_KEY_ID=$$TF_VAR_R2_ACCESS_KEY_ID \
		AWS_SECRET_ACCESS_KEY=$$TF_VAR_R2_SECRET_ACCESS_KEY \
		terraform -chdir=infra/$(MOD) init $(backend_config)

upgradeinit:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		AWS_ACCESS_KEY_ID=$$TF_VAR_R2_ACCESS_KEY_ID \
		AWS_SECRET_ACCESS_KEY=$$TF_VAR_R2_SECRET_ACCESS_KEY \
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
		AWS_ACCESS_KEY_ID=$$TF_VAR_R2_ACCESS_KEY_ID \
		AWS_SECRET_ACCESS_KEY=$$TF_VAR_R2_SECRET_ACCESS_KEY \
		terraform -chdir=infra/$(MOD) init -migrate-state $(backend_config)

# Dump diagramdb from local k3s postgres to ~/backups

dump:
	@mkdir -p ~/backups
	@kubectl exec -n database svc/postgres -- pg_dump -U diagram -d diagramdb \
		| gzip > ~/backups/diagramdb-$$(date +%F-%H%M).sql.gz
	@echo "Backup saved: ~/backups/diagramdb-$$(date +%F-%H%M).sql.gz"

secrets:
	infisical secrets generate-example-env --env=dev --path=/terraform
