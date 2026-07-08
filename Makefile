MOD ?=
ENV ?= dev
SECRETS_PATH ?= /terraform

.PHONY: init upgradeinit plan out apply destroy fmt validate infisical-plan infisical-apply

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

infisical-plan:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) plan

infisical-apply:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		terraform -chdir=infra/$(MOD) apply
