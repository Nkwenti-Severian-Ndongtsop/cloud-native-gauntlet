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
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11.0"
    }
  }
}

# Get kubeconfig from the VM and set up providers
resource "null_resource" "setup_kubeconfig" {
  # This will run during the apply phase
  provisioner "local-exec" {
    command = <<-EOT
      # Create .kube directory if it doesn't exist
      mkdir -p ${path.module}/.kube
      
      # Check VM status and start if needed
      echo "Checking VM status..."
      VM_STATUS=$(vagrant status --machine-readable | grep "state," | cut -d',' -f4)
      echo "VM status: $VM_STATUS"
      
      if [ "$VM_STATUS" != "running" ]; then
        echo "VM is not running (status: $VM_STATUS). Starting VM..."
        if ! vagrant up; then
          echo "Failed to start VM"
          exit 1
        fi
        echo "VM started successfully"
        
        # Wait a bit for K3s to be ready
        echo "Waiting for K3s to be ready..."
        sleep 30
      else
        echo "VM is already running"
      fi
      
      # Get kubeconfig from VM and update the server IP
      echo "Fetching kubeconfig from VM..."
      if ! vagrant ssh -c "sudo cat /etc/rancher/k3s/k3s.yaml" > ${path.module}/.kube/k3s-config 2>/dev/null; then
        echo "Failed to fetch kubeconfig from VM"
        exit 1
      fi
      
      # Update the server IP in the kubeconfig
      echo "Updating kubeconfig with VM IP..."
      if ! sed 's/127.0.0.1/192.168.56.10/g' ${path.module}/.kube/k3s-config > ${path.module}/.kube/config; then
        echo "Failed to update kubeconfig with VM IP"
        exit 1
      fi
      
      # Set proper permissions on the kubeconfig file
      chmod 600 ${path.module}/.kube/config
      
      echo "Kubeconfig has been set up at ${path.module}/.kube/config"
    EOT
  }

  # This ensures the resource is always recreated to get fresh kubeconfig
  triggers = {
    always_run = "${timestamp()}"
  }
}

# Configure Kubernetes provider with dynamic kubeconfig
provider "kubernetes" {
  config_path    = "${path.module}/.kube/config"
  config_context = "default"
}

provider "helm" {
  kubernetes {
    config_path    = "${path.module}/.kube/config"
    config_context = "default"
  }
}

# Create a local file with the VM's IP for /etc/hosts
resource "local_file" "hosts_file" {
  filename = "${path.module}/../hosts"
  content  = <<-EOT
    192.168.56.10 keycloak.local gitea.local todo.local
  EOT
}

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
  depends_on = [null_resource.vagrant_up]

  # This will be triggered when the VM IP changes
  triggers = {
    master_ip = var.k3s_master_ip
  }

  # Copy kubeconfig from VM to local machine
  provisioner "local-exec" {
    command = <<-EOT
      bash -lc '
        cd ${path.module}/..
        # Get VM SSH config
        vagrant ssh-config cloud-gauntlet > /tmp/vagrant-ssh-config
        # Copy kubeconfig from VM
        scp -F /tmp/vagrant-ssh-config cloud-gauntlet:/etc/rancher/k3s/k3s.yaml ${path.module}/kubeconfig
        # Update kubeconfig to use VM IP instead of 127.0.0.1
        sed -i "s/127.0.0.1/"${var.k3s_master_ip}"/g" ${path.module}/kubeconfig
        # Set proper permissions
        chmod 600 ${path.module}/kubeconfig
        
        # Copy kubeconfig to default location for kubectl
        mkdir -p ~/.kube
        cp ${path.module}/kubeconfig ~/.kube/config
      '
    EOT
  }

  # Clean up local kubeconfig when destroying
  provisioner "local-exec" {
    when    = destroy
    command = "rm -f ${path.module}/kubeconfig ~/.kube/config"
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

# Preload images into local registry inside the VM before workloads
resource "null_resource" "preload_images" {
  depends_on = [null_resource.provision_infrastructure]

  triggers = {
    script_hash = filesha1("${path.module}/../scripts/prepare-offline-images.sh")
  }

  provisioner "local-exec" {
    command = <<-EOC
      bash -lc 'cd ${path.module}/.. && vagrant ssh cloud-gauntlet -c "bash -lc \"cd /vagrant && bash scripts/prepare-offline-images.sh\""'
    EOC
  }

  provisioner "local-exec" {
    command = "bash -lc 'true'"
    when    = destroy
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
    null_resource.setup_kubeconfig,
    null_resource.k8s_verify_nodes,
    local_file.ansible_inventory,
    local_file.ansible_vars,
    local_file.hosts_file
  ]

  # This will run after the VM is fully provisioned
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Applying workloads..."
      
      # Ensure we're in the correct directory
      cd ${path.module}/workloads
      
      # Copy the kubeconfig to the workloads directory
      echo "Copying kubeconfig to workloads directory..."
      mkdir -p ./.kube
      cp ../.kube/config ./.kube/config
      chmod 600 ./.kube/config
      
      # Initialize Terraform
      echo "Initializing Terraform..."
      if ! terraform init -upgrade -input=false; then
        echo "Terraform initialization failed"
        exit 1
      fi
      
      # Apply the Terraform configuration
      echo "Applying Terraform configuration..."
      if ! terraform apply -auto-approve; then
        echo "Terraform apply failed"
        exit 1
      fi
      
      echo "Workloads applied successfully"
    EOT
  }

  # This ensures the resource is always recreated to apply any changes
  triggers = {
    always_run = "${timestamp()}"
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