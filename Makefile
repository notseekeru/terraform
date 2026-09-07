MOD ?=
ENV ?= dev
SECRETS_PATH ?= /terraform

# R2 state-bucket creds are namespaced TF_VAR_R2_* so they never collide with the
# AWS provider's native AWS_ACCESS_KEY_ID. Non-secret backend config (bucket, key,
# region, endpoint shape, skip_*/use_lockfile) comes from the committed per-module
# template infra/<MOD>/backend.tfbackend.tpl, rendered by scripts/render-tfbackend.sh
# at init-time (R2 account id substituted from $TF_VAR_R2_ACCOUNT_ID). Only the two
# secret keys are passed as -backend-config flags below, expanding from
# infisical-injected TF_VAR_R2_*.
TFBACKEND_TEMPLATE = infra/$(MOD)/backend.tfbackend.tpl
TFBACKEND_OUT = infra/$(MOD)/.terraform/backend.generated.tfbackend
# Path terraform consumes AFTER -chdir=infra/$(MOD), so it is module-relative.
TFBACKEND_OUT_REL = .terraform/backend.generated.tfbackend
backend_render = scripts/render-tfbackend.sh $(MOD) $(TFBACKEND_TEMPLATE) $(TFBACKEND_OUT)
backend_creds = -backend-config="access_key=$$TF_VAR_R2_ACCESS_KEY_ID" \
	-backend-config="secret_key=$$TF_VAR_R2_SECRET_ACCESS_KEY"
# Guarantee the AWS provider never sees an R2 endpoint, even if a stale
# AWS_ENDPOINT_URL_S3 is still present in Infisical and injected by `infisical run`.
# The R2 endpoint reaches the backend only via the rendered .tfbackend at init.
no_r2_endpoint = unset AWS_ENDPOINT_URL_S3 AWS_ENDPOINT_URL AWS_S3_ENDPOINT; \
	AWS_EC2_METADATA_DISABLED=true

.PHONY: fmt validate init upgradeinit reconfigure plan apply destroy migrate dump secrets verify-db-auth nuke-list

fmt:
	terraform -chdir=infra/$(MOD) fmt

validate:
	terraform -chdir=infra/$(MOD) validate

# Backend-only targets render the template then bind R2. They run through a shell
# so the $$TF_VAR_R2_* cred refs expand from infisical's injected env. plan/apply/
# destroy run afterwards with NO R2 endpoint in their env, so the AWS provider in
# infra/aws defaults to real S3 and needs no endpoints.s3 override.
init:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- /bin/sh -c \
		'$(backend_render) && terraform -chdir=infra/$(MOD) init -backend-config=$(TFBACKEND_OUT_REL) $(backend_creds)'

upgradeinit:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- /bin/sh -c \
		'$(backend_render) && terraform -chdir=infra/$(MOD) init -upgrade -backend-config=$(TFBACKEND_OUT_REL) $(backend_creds)'

plan:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- /bin/sh -c \
		'$(no_r2_endpoint) terraform -chdir=infra/$(MOD) plan'

refresh:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- /bin/sh -c \
		'$(no_r2_endpoint) terraform -chdir=infra/$(MOD) refresh'

apply:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- /bin/sh -c \
		'$(no_r2_endpoint) terraform -chdir=infra/$(MOD) apply'

destroy:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- /bin/sh -c \
		'$(no_r2_endpoint) terraform -chdir=infra/$(MOD) destroy'

# Sweeps billable drift across the account via nuke-config.yaml. aws-nuke has
# NO tag-based opt-out. the config excludes KMS + IAM so this never orphans the
# credential/encryption chain that reprovisions the stack (see nuke-config.yaml,
# resource-types.excludes). Still: confirm `make destroy` first, because anything
# Terraform built that is NOT in the exclude set WILL be deleted out-of-band,
# desyncing remote state in R2.
NUKE_CFG ?= nuke-config.yaml

nuke-list:
	@echo '== AWS-NUKE DRY RUN (nothing deleted) =='
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		aws-nuke -c $(NUKE_CFG)

reconfigure:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- /bin/sh -c \
		'$(backend_render) && terraform -chdir=infra/$(MOD) init -reconfigure -backend-config=$(TFBACKEND_OUT_REL) $(backend_creds)'

# One-time (per module): push local state to R2. Only needed on first backend setup.
migrate:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- /bin/sh -c \
		'$(backend_render) && terraform -chdir=infra/$(MOD) init -migrate-state -backend-config=$(TFBACKEND_OUT_REL) $(backend_creds)'

# Dump diagramdb from local k3s postgres to ~/backups

dump:
	@mkdir -p ~/backups
	@kubectl exec -n database svc/postgres -- pg_dump -U diagram -d diagramdb \
		| gzip > ~/backups/diagramdb-$$(date +%F-%H%M).sql.gz
	@echo "Backup saved: ~/backups/diagramdb-$$(date +%F-%H%M).sql.gz"

verify-db-auth:
	@echo "Authenticating as diagram over the Service DNS (TCP path clients use)..."
	@infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
	  kubectl run db-auth-probe --rm -i --restart=Never --image=postgres:16-alpine -- \
	  psql "postgresql://diagram:$$POSTGRES_PASSWORD@postgres.database.svc.cluster.local:5432/diagramdb" -c 'select 1'
	@echo "OK: role authenticates over TCP"

# Retrieves and prints secrets variable name but not the value itself(left blank for security reasons).
secrets:
	infisical secrets generate-example-env --env=dev --path=/terraform
