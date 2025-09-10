[all:vars]
ansible_user=vagrant
ansible_ssh_private_key_file=.vagrant/machines/cloud-gauntlet/virtualbox/private_key
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[k3s_masters]
cloud-gauntlet ansible_host=${master_ip} hostname=cloud-gauntlet

[k3s_workers]
cloud-gauntlet ansible_host=${master_ip} hostname=cloud-gauntlet

[registry]
cloud-gauntlet ansible_host=${master_ip} hostname=cloud-gauntlet

[dns]
cloud-gauntlet ansible_host=${master_ip} hostname=cloud-gauntlet
