
# -*- mode: ruby -*-
# vi: set ft=ruby :

# Global configuration
VAGRANTFILE_API_VERSION = "2"

# VM Configuration
NODES = {
  'cloud-gauntlet' => {
    :ip => '192.168.56.10',
    :cpus => 4,
    :memory => 6144,
    :roles => ['master'],
    :hostname => 'cloud-gauntlet'
  }
}

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  # Configure the base box
  config.vm.box = "ubuntu/focal64"
  config.vm.box_check_update = false
  
  # Disable automatic box update checking
  if Vagrant.has_plugin?("vagrant-vbguest")
    config.vbguest.auto_update = false
  end

  # Configure each node
  NODES.each do |node_name, node_config|
    config.vm.define node_name do |node|
      node.vm.hostname = node_name
      # Use private network for better network isolation
      node.vm.network "private_network", ip: node_config[:ip]
      
      # Configure DNS servers using systemd-resolved
      node.vm.provision "shell", inline: <<-SHELL
        # Configure systemd-resolved to use Google's DNS
        sudo mkdir -p /etc/systemd/resolved.conf.d
        echo '[Resolve]' | sudo tee /etc/systemd/resolved.conf.d/dns_servers.conf
        echo 'DNS=8.8.8.8 8.8.4.4' | sudo tee -a /etc/systemd/resolved.conf.d/dns_servers.conf
        
        # Create a symlink for /etc/resolv.conf to use systemd-resolved
        sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
        
        # Restart systemd-resolved to apply changes
        sudo systemctl restart systemd-resolved
        
        # Test DNS resolution
        echo 'Testing DNS resolution:'
        ping -c 3 google.com || echo 'DNS resolution failed'
      SHELL
      
      # VM resources
      node.vm.provider "virtualbox" do |vb|
        vb.name = node_name
        vb.memory = node_config[:memory]
        vb.cpus = node_config[:cpus]
        vb.customize ["modifyvm", :id, "--ioapic", "on"]
        vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
        vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      end
      
      # Provisioning with Ansible
      node.vm.provision "ansible" do |ansible|
        ansible.playbook = "ansible/site.yml"
        ansible.inventory_path = "ansible/hosts.ini"
        ansible.limit = "all"
        ansible.extra_vars = {
          node_roles: node_config[:roles],
          k3s_master_ip: node_config[:ip]
        }
      end
    end
  end
  
  # Hosts file update (optional if vagrant-hostmanager is installed)
  if false && Vagrant.has_plugin?("vagrant-hostmanager")
    config.hostmanager.enabled = true
    config.hostmanager.manage_host = true
    config.hostmanager.ignore_private_ip = false
    config.hostmanager.include_offline = true
    config.hostmanager.aliases = NODES.values.map { |node| node[:hostname] || node[:ip] }
  else
    puts "Warning: vagrant-hostmanager plugin not found. Hosts file won't be updated automatically."
    puts "Install it with: vagrant plugin install vagrant-hostmanager"
  end
end