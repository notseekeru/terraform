MOD ?=
ENV ?= prod
SECRETS_PATH ?= /consumers/terraform
# A contended or stale state lock fails after 30s instead of hanging the run (README operating rules).
LOCK ?= -lock-timeout=30s

# R2 state-bucket creds are namespaced TF_VAR_R2_* so they never collide with the
# AWS provider's native AWS_ACCESS_KEY_ID. Every backend setting reaches init as a
# -backend-config flag and is stored in the module's .terraform directory, so later
# runs do not need it again: bucket/key/creds expand from infisical-injected
# TF_VAR_R2_*, and endpoints.s3 comes from TF_VAR_R2_ENDPOINT (the full
# https://<account>.r2.cloudflarestorage.com URL). The AWS_ENDPOINT_URL_S3
# fallback keeps init working until that secret is renamed; plan/apply pass no
# backend flags, and the provider pin below covers the old var meanwhile.
backend_config = -backend-config="bucket=$$TF_VAR_R2_BUCKET" \
	-backend-config="key=terraform/$(MOD)/terraform.tfstate" \
	-backend-config="region=auto" \
	-backend-config="access_key=$$TF_VAR_R2_ACCESS_KEY_ID" \
	-backend-config="secret_key=$$TF_VAR_R2_SECRET_ACCESS_KEY" \
	-backend-config="endpoints={s3=\"$${TF_VAR_R2_ENDPOINT:-$$AWS_ENDPOINT_URL_S3}\"}"
# infra/aws/provider.tf pins endpoints.s3 to real AWS S3: that pin, not the
# environment, is what keeps aws_s3_bucket* resources in AWS.

LOCK_ID ?=

.PHONY: fmt validate init upgradeinit reconfigure plan apply destroy migrate dump secrets verify-db-auth nuke-list unlock

fmt:
	terraform -chdir=infra/$(MOD) fmt

validate:
	terraform -chdir=infra/$(MOD) validate

# Backend targets exec terraform through a shell so the $$TF_VAR_R2_* refs in
# backend_config expand from infisical's injected env (infisical itself execs
# directly and would otherwise pass them through unexpanded as empty strings).
# plan/apply/refresh/destroy run un-wrapped against the stored backend config.
init:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- /bin/sh -c \
		'terraform -chdir=infra/$(MOD) init $(backend_config)'

upgradeinit:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- /bin/sh -c \
		'terraform -chdir=infra/$(MOD) init -upgrade $(backend_config)'

plan:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) plan $(LOCK)

refresh:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) refresh $(LOCK)

apply:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) apply $(LOCK)

destroy:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) destroy $(LOCK)

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

# Force-unlock drops the state lock unconditionally. Only for a dead run: a live
# apply keeps writing while the lock is gone, which corrupts remote state.
unlock:
	@test -n "$(LOCK_ID)" || { echo 'LOCK_ID required (from the lock error)'; exit 1; }
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) force-unlock $(LOCK_ID)

reconfigure:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- /bin/sh -c \
		'terraform -chdir=infra/$(MOD) init -reconfigure $(backend_config)'

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

verify-db-auth:
	@echo "Authenticating as diagram over the Service DNS (TCP path clients use)..."
	@infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
	  kubectl run db-auth-probe --rm -i --restart=Never --image=postgres:18-alpine -- \
	  psql "postgresql://diagram:$$POSTGRES_PASSWORD@postgres.database.svc.cluster.local:5432/diagramdb" -c 'select 1'
	@echo "OK: role authenticates over TCP"

# Retrieves and prints secrets variable name but not the value itself(left blank for security reasons).
secrets:
	infisical secrets generate-example-env --env=$(ENV) --path=$(SECRETS_PATH)
