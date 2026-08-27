MOD ?=
ENV ?= dev
SECRETS_PATH ?= /terraform

# R2 state-bucket creds are namespaced TF_VAR_R2_* so they never collide with the
# AWS provider's native AWS_ACCESS_KEY_ID. The deprecated `endpoint` backend-config
# key is rejected by Terraform >=1.5, so the R2 URL is injected instead via the
# modern env-var source AWS_ENDPOINT_URL_S3 (= endpoints.s3). backend_config keeps
# the flat, non-deprecated keys; bucket/key expand from infisical-injected TF_VAR_R2_*.
backend_config = -backend-config="bucket=$$TF_VAR_R2_BUCKET" \
	-backend-config="key=terraform/$(MOD)/terraform.tfstate" \
	-backend-config="region=auto" \
	-backend-config="access_key=$$TF_VAR_R2_ACCESS_KEY_ID" \
	-backend-config="secret_key=$$TF_VAR_R2_SECRET_ACCESS_KEY"

.PHONY: fmt validate init upgradeinit plan apply destroy migrate dump secrets

fmt:
	terraform -chdir=infra/$(MOD) fmt

validate:
	terraform -chdir=infra/$(MOD) validate

# The backend targets exec terraform through a shell so the \$$TF_VAR_R2_* refs in
# backend_config expand from infisical's injected env (infisical itself execs directly
# and would otherwise pass them verbatim as empty strings).
init:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- /bin/sh -c \
		'terraform -chdir=infra/$(MOD) init $(backend_config)'

upgradeinit:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- /bin/sh -c \
		'terraform -chdir=infra/$(MOD) init -upgrade $(backend_config)'

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
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- /bin/sh -c \
		'terraform -chdir=infra/$(MOD) init -migrate-state $(backend_config)'

# Dump diagramdb from local k3s postgres to ~/backups

dump:
	@mkdir -p ~/backups
	@kubectl exec -n database svc/postgres -- pg_dump -U diagram -d diagramdb \
		| gzip > ~/backups/diagramdb-$$(date +%F-%H%M).sql.gz
	@echo "Backup saved: ~/backups/diagramdb-$$(date +%F-%H%M).sql.gz"

secrets:
	infisical secrets generate-example-env --env=dev --path=/terraform
