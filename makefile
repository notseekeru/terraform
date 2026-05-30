TF_DIR := infrastructure

.PHONY: init plan plan-out apply-plan deploy destroy

init:
	terraform -chdir=$(TF_DIR) init

plan:
	terraform -chdir=$(TF_DIR) plan -var-file=../secrets.tfvars

plan-out:
	terraform -chdir=$(TF_DIR) plan -var-file=../secrets.tfvars -out=tfplan

apply-plan:
	terraform -chdir=$(TF_DIR) apply tfplan

deploy:
	terraform -chdir=$(TF_DIR) apply -auto-approve -var-file=../secrets.tfvars

destroy:
	terraform -chdir=$(TF_DIR) destroy -auto-approve -var-file=../secrets.tfvars