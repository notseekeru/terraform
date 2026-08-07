MOD ?=
ENV ?= dev
SECRETS_PATH ?= /terraform

.PHONY: init upgradeinit plan out apply destroy fmt validate infi-plan infi-apply infi-destroy dump

init:
	terraform -chdir=infra/$(MOD) init

upgradeinit:
	terraform -chdir=infra/$(MOD) init -upgrade

plan:
	terraform -chdir=infra/$(MOD) plan -var-file=../../secrets.tfvars

out:
	terraform -chdir=infra/$(MOD) plan -var-file=../../secrets.tfvars -out=tfplan

apply:
	terraform -chdir=infra/$(MOD) apply tfplan

destroy:
	terraform -chdir=infra/$(MOD) destroy -var-file=../../secrets.tfvars

fmt:
	terraform -chdir=infra/$(MOD) fmt

validate:
	terraform -chdir=infra/$(MOD) validate

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

# Dump the diagramdb from the local k3s postgres to ~/backups
dump:
	@mkdir -p ~/backups
	@kubectl exec -n database svc/postgres -- pg_dump -U diagram -d diagramdb \
		| gzip > ~/backups/diagramdb-$$(date +%F-%H%M).sql.gz
	@echo "Backup saved: ~/backups/diagramdb-$$(date +%F-%H%M).sql.gz"
