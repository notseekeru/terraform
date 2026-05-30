.PHONY: deploy plan destroy

plan:
	terraform plan

deploy:
	terraform apply -auto-approve
	ansible-playbook -i inventory.ini site.yml # Ensure this triggers only after
Terraform completes

destroy:
	terraform destroy -auto-approve