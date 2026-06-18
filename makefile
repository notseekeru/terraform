TF_DIR := infrastructure

.PHONY: init plan out apply deploy destroy fmt validate

init:
	terraform -chdir=$(TF_DIR) init

upgradeinit:
	terraform -chdir=$(TF_DIR) init -upgrade

plan:
	terraform -chdir=$(TF_DIR) plan -var-file=../secrets.tfvars

out:
	terraform -chdir=$(TF_DIR) plan -var-file=../secrets.tfvars -out=tfplan

apply:
	terraform -chdir=$(TF_DIR) apply tfplan

destroy:
	terraform -chdir=$(TF_DIR) destroy -auto-approve -var-file=../secrets.tfvars

fmt:
	terraform -chdir=$(TF_DIR) fmt

validate:
	terraform -chdir=$(TF_DIR) validate
