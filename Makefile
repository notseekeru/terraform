MOD ?= infra/droplet

.PHONY: init upgradeinit plan out apply destroy fmt validate

init:
	terraform -chdir=$(MOD) init

upgradeinit:
	terraform -chdir=$(MOD) init -upgrade

plan:
	terraform -chdir=$(MOD) plan -var-file=../../secrets.tfvars

out:
	terraform -chdir=$(MOD) plan -var-file=../../secrets.tfvars -out=tfplan

apply:
	terraform -chdir=$(MOD) apply tfplan

destroy:
	terraform -chdir=$(MOD) destroy -var-file=../../secrets.tfvars

fmt:
	terraform -chdir=$(MOD) fmt

validate:
	terraform -chdir=$(MOD) validate
