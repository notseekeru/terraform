MODULE ?= infra/droplet

.PHONY: init upgradeinit plan out apply fmt validate

init:
	terraform -chdir=$(MODULE) init

upgradeinit:
	terraform -chdir=$(MODULE) init -upgrade

plan:
	terraform -chdir=$(MODULE) plan -var-file=../secrets.tfvars

out:
	terraform -chdir=$(MODULE) plan -var-file=../secrets.tfvars -out=tfplan

apply:
	terraform -chdir=$(MODULE) apply tfplan

fmt:
	terraform -chdir=$(MODULE) fmt

validate:
	terraform -chdir=$(MODULE) validate
