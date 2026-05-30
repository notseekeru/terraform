TF_DIR := infrastructure

.PHONY: plan deploy destroy

plan:
	terraform -chdir=$(TF_DIR) plan

deploy:
	terraform -chdir=$(TF_DIR) apply -auto-approve
	# Add your ansible trigger here, ensuring it points to your inventory
	# ansible-playbook -i ../ansible/inventory.ini ../ansible/site.yml

destroy:
	terraform -chdir=$(TF_DIR) destroy -auto-approve