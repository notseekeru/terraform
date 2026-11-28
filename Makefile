MOD ?=
ENV ?= prod
SECRETS_PATH ?= /consumers/terraform
# A contended or stale state lock fails after 30s instead of hanging the run (README operating rules).
LOCK ?= -lock-timeout=30s

# State lives in Postgres (Neon). The pg backend reads PG_CONN_STR from the
# infisical-injected env, and PG_SCHEMA_NAME keeps one schema per module.
export PG_SCHEMA_NAME := tf_$(MOD)
# infra/aws/provider.tf pins endpoints.s3 to real AWS S3: that pin, not the
# environment, is what keeps aws_s3_bucket* resources in AWS.

LOCK_ID ?=

.PHONY: fmt validate init upgradeinit reconfigure plan apply destroy migrate dump secrets verify-db-auth nuke-list unlock

fmt:
	terraform -chdir=infra/$(MOD) fmt

validate:
	terraform -chdir=infra/$(MOD) validate

# Backend targets need no shell: the pg backend reads PG_CONN_STR and
# PG_SCHEMA_NAME from the environment that infisical injects.
init:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) init

upgradeinit:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) init -upgrade

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
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) init -reconfigure

# One-time (per module): move state into the pg backend.
migrate:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) init -migrate-state

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
