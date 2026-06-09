# Terraform

This repository contains Terraform code for provisioning infrastructure on my personal cloud. It includes modules for setting up virtual machines, networking, and other resources.

Currently, the code is designed to work with DigitalOcean, but it can be adapted for other cloud providers with some modifications. The main goal is to automate the deployment and management of my personal cloud infrastructure using Terraform.

## Requirements

- Terraform 1.0 or higher
- A DigitalOcean API token set in the `DIGITALOCEAN_TOKEN` environment variable
- An SSH key (or multiple keys) added to your DigitalOcean account for accessing the provisioned virtual machines

## Usage

```bash
# Install required dependencies:
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common

# Add the HashiCorp GPG key:
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# Add the HashiCorp repository:
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# Update and install Terraform:
sudo apt-get update && sudo apt-get install terraform

# Verify the installation:
terraform -v
```
