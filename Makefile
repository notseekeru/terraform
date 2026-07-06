MODULE ?=

.PHONY: init upgradeinit plan out apply destroy fmt validate

init:
	terraform -chdir=infra/$(MODULE) init

upgradeinit:
	terraform -chdir=infra/$(MODULE) init -upgrade

plan:
	terraform -chdir=infra/$(MODULE) plan -var-file=../../secrets.tfvars

out:
	terraform -chdir=infra/$(MODULE) plan -var-file=../../secrets.tfvars -out=tfplan

apply:
	terraform -chdir=infra/$(MODULE) apply tfplan

destroy:
	terraform -chdir=infra/$(MODULE) destroy -var-file=../../secrets.tfvars

fmt:
	terraform -chdir=infra/$(MODULE) fmt

validate:
	terraform -chdir=infra/$(MODULE) validate
