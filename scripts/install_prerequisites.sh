#!/bin/bash
set -e

echo "Updating package list..."
sudo apt-get update -y

echo "Checking for VirtualBox installation..."
if ! dpkg -s virtualbox >/dev/null 2>&1; then
  echo "Installing VirtualBox..."
  sudo apt-get install -y virtualbox virtualbox-qt virtualbox-dkms
else
  echo "VirtualBox is already installed. Skipping installation."
fi

echo "Checking for Ansible installation..."
if ! command -v ansible >/dev/null 2>&1; then
  echo "Installing Ansible..."
  sudo apt-get install -y software-properties-common
  sudo add-apt-repository --yes --update ppa:ansible/ansible
  sudo apt-get install -y ansible
else
  echo "Ansible is already installed. Skipping installation."
fi

echo "Checking for Vagrant installation..."
if ! command -v vagrant >/dev/null 2>&1; then
  echo "Installing Vagrant..."
  sudo apt-get install -y vagrant
else
  echo "Vagrant is already installed. Skipping installation."
fi

echo "Checking for Terraform installation..."
if ! command -v terraform >/dev/null 2>&1; then
  echo "Installing Terraform..."
  sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
  wget -O- https://apt.releases.hashicorp.com/gpg | \
    gpg --dearmor | \
    sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
  gpg --no-default-keyring \
    --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    --fingerprint
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt-get update -y
  sudo apt-get install -y terraform
else
  echo "Terraform is already installed. Skipping installation."
fi

echo "Prerequisites installation script completed."