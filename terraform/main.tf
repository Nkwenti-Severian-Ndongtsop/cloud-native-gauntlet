# Configure the null provider as a placeholder for infrastructure definition
# In a real-world scenario, this would be a cloud provider like AWS, Azure, GCP,
# or a virtualization provider like VirtualBox or Libvirt.
terraform {
  required_version = ">= 1.4.0"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.2"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4.0"
    }
  }
}

provider "null" {}

# Kubernetes provider; will use the kubeconfig file fetched from the VM
# Intentionally no kubernetes/helm providers at root to avoid early provider init

# Bring up cloud-gauntlet VM using Vagrant
resource "null_resource" "vagrant_up" {
  provisioner "local-exec" {
    command = <<-EOT
      bash -lc '
        cd ${path.module}/..
        state=$(vagrant status cloud-gauntlet --machine-readable | awk -F, "/,state-human-short,/ {st=\$4} END {print st}")
        case "$state" in
          running)
            echo "VM already running" ;;
          poweroff|aborted|saved)
            echo "Starting VM without provisioning" ; vagrant up cloud-gauntlet --no-provision ;;
          *)
            echo "Bringing up VM with provisioning" ; vagrant up cloud-gauntlet --provision ;;
        esac
      '
    EOT
  }
  
  provisioner "local-exec" {
    when = destroy
    command = "bash -lc 'cd ${path.module}/.. && vagrant destroy cloud-gauntlet -f'"
  }
}

# Fetch kubeconfig from the cloud-gauntlet VM and rewrite the API server address to VM IP
resource "null_resource" "fetch_kubeconfig" {
  depends_on = [null_resource.provision_infrastructure]

  triggers = {
    master_ip  = var.k3s_master_ip
  }

  provisioner "local-exec" {
    command = "bash -lc 'vagrant ssh cloud-gauntlet -c \"sudo cat /etc/rancher/k3s/k3s.yaml\" > \"${path.module}/kubeconfig.raw\" && sed -E \"/^Warning:|^Install it with:/d;s#server: https?://127.0.0.1:6443#server: https://${var.k3s_master_ip}:6443#g\" \"${path.module}/kubeconfig.raw\" > \"${path.module}/kubeconfig\" && rm -f \"${path.module}/kubeconfig.raw\"'"
  }
}

# Ensure master is control-plane only and worker runs workloads
resource "null_resource" "k8s_node_prep" {
  depends_on = [null_resource.fetch_kubeconfig]

  provisioner "local-exec" {
    # Run kubectl commands inside the VM where kubectl is available
    # In single VM setup, we only have one node (cloud-gauntlet-master)
    command = "bash -lc 'vagrant ssh cloud-gauntlet -c \"sudo kubectl label nodes cloud-gauntlet-master node-role.kubernetes.io/control-plane=true --overwrite && sudo kubectl label nodes cloud-gauntlet-master node-role.kubernetes.io/worker=true --overwrite\"'"
  }
}

# Optional: verify nodes state
resource "null_resource" "k8s_verify_nodes" {
  depends_on = [null_resource.k8s_node_prep]

  triggers = {
    master_ip  = var.k3s_master_ip
    worker_ips = join(",", var.k3s_worker_ips)
  }

  provisioner "local-exec" {
    command = "bash -lc 'vagrant ssh cloud-gauntlet -c \"sudo kubectl get nodes -o wide\"'"
  }
}

#
# Auto-discover and deploy local Helm charts
#

locals {
  # Resolve absolute path to helm charts root using a relative input
  helm_charts_root = abspath("${path.module}/../${var.helm_charts_root_rel}")

  # Find all Chart.yaml files under the charts root
  helm_chart_files = fileset(local.helm_charts_root, "**/Chart.yaml")

  # Derive chart directories and names from Chart.yaml paths
  helm_chart_dirs  = [for f in local.helm_chart_files : dirname("${local.helm_charts_root}/${f}")]
  helm_chart_names = [for d in local.helm_chart_dirs : basename(d)]

  # Map of release_name => chart_directory
  helm_releases = { for d in local.helm_chart_dirs : basename(d) => d }

  # All files under helm/ to detect changes
  helm_all_files = fileset("${path.module}/../helm", "**")
  helm_files_hash = md5(join(",", [for f in local.helm_all_files : filesha1("${path.module}/../helm/${f}")]))
}

# Apply workloads via a child Terraform run after kubeconfig is fetched
resource "null_resource" "workloads_apply" {
  depends_on = [
    null_resource.k8s_node_prep,
    null_resource.fetch_kubeconfig
  ]

  triggers = {
    helm_hash = local.helm_files_hash
  }

  provisioner "local-exec" {
    command = "bash -lc 'KCFG=\"$(readlink -f ${path.module}/kubeconfig)\" && terraform -chdir=./workloads init -upgrade -input=false && terraform -chdir=./workloads apply -var kubeconfig_path=\"$KCFG\" -auto-approve'"
  }
}

# Generate inventory file for Ansible
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    master_ip = var.k3s_master_ip
    worker_ips = var.k3s_worker_ips
  })
  filename = "${path.module}/../ansible/hosts.ini"
}

# Generate Ansible variables
resource "local_file" "ansible_vars" {
  content = templatefile("${path.module}/group_vars.tpl", {
    master_ip = var.k3s_master_ip
    worker_ips = var.k3s_worker_ips
  })
  filename = "${path.module}/../ansible/group_vars/all.yml"
}

# Provision infrastructure with Ansible (runs on the machine where Terraform is executed)
resource "null_resource" "provision_infrastructure" {
  depends_on = [null_resource.vagrant_up, local_file.ansible_inventory, local_file.ansible_vars]
  
  triggers = {
    inventory_hash = local_file.ansible_inventory.content_md5
    vars_hash = local_file.ansible_vars.content_md5
  }

  provisioner "local-exec" {
    # Run Ansible from host to provision the VM
    command = "bash -lc 'cd ${path.module}/.. && ansible-playbook -i ansible/hosts.ini ansible/site.yml'"
  }
}

# Define variables for K3s cluster
variable "k3s_master_ip" {
  description = "The IP address of the K3s master node."
  type        = string
  default     = "192.168.56.10" # Matches Vagrantfile
}

variable "k3s_worker_ips" {
  description = "A list of IP addresses for K3s worker nodes."
  type        = list(string)
  default     = ["192.168.56.11"] # Matches Vagrantfile
}

# Kubeconfig path used by providers (running inside k3s-master VM by default)
variable "kubeconfig_path" {
  description = "Optional override path to kubeconfig for Kubernetes and Helm providers. If empty, Terraform will fetch from the master VM."
  type        = string
  default     = ""
}

# Root directory that contains local Helm chart folders
variable "helm_charts_root_rel" {
  description = "Relative path (from repository root) to directory with Helm chart folders."
  type        = string
  default     = "helm"
}

# Output the master IP
output "k3s_master_ip" {
  value = var.k3s_master_ip
}

# Output the worker IPs
output "k3s_worker_ips" {
  value = var.k3s_worker_ips
}