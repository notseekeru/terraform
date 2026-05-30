# Terraform

This repository contains Terraform code for provisioning infrastructure on my personal cloud. It includes modules for setting up virtual machines, networking, and other resources.

## Requirements

- Terraform 1.0 or higher
- A DigitalOcean API token set in the `DIGITALOCEAN_TOKEN` environment variable

## Usage

- Install required dependencies:
  sudo apt-get update && sudo apt-get install -y gnupg software-properties-common

- Add the HashiCorp GPG key:
  wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

- Add the HashiCorp repository:
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

- Update and install Terraform:
  sudo apt-get update && sudo apt-get install terraform

- Verify the installation:
  terraform -v
