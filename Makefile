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
		bash -c 'for v in DO_TOKEN CLOUDFLARE_TOKEN GITHUB_PAT GITHUB_USERNAME GITOPS_REPO_URL diagram_api_key; do export TF_VAR_$$v=$${!v}; done; terraform -chdir=infra/$(MOD) plan'

infisical-apply:
	infisical run --path $(SECRETS_PATH) --env $(ENV) -- \
		bash -c 'for v in DO_TOKEN CLOUDFLARE_TOKEN GITHUB_PAT GITHUB_USERNAME GITOPS_REPO_URL diagram_api_key; do export TF_VAR_$$v=$${!v}; done; terraform -chdir=infra/$(MOD) apply'
