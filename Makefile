MOD ?= droplet
MOD_DIR := infra/$(MOD)

.PHONY: init upgradeinit plan out apply destroy fmt validate

init:
	terraform -chdir=$(MOD_DIR) init

upgradeinit:
	terraform -chdir=$(MOD_DIR) init -upgrade

plan:
	terraform -chdir=$(MOD_DIR) plan -var-file=../../secrets.tfvars

out:
	terraform -chdir=$(MOD_DIR) plan -var-file=../../secrets.tfvars -out=tfplan

apply:
	terraform -chdir=$(MOD_DIR) apply tfplan

destroy:
	terraform -chdir=$(MOD_DIR) destroy -var-file=../../secrets.tfvars

fmt:
	terraform -chdir=$(MOD_DIR) fmt

validate:
	terraform -chdir=$(MOD_DIR) validate
