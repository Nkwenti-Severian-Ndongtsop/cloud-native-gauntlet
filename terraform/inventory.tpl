[all:vars]
ansible_user=vagrant
ansible_ssh_private_key_file=~/.vagrant.d/insecure_private_key
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[k3s_masters]
k3s-master ansible_host=${master_ip} hostname=k3s-master

[k3s_workers]
%{ for ip in worker_ips ~}
k3s-worker-${ip} ansible_host=${ip} hostname=k3s-worker
%{ endfor ~}

[registry]
k3s-master ansible_host=${master_ip} hostname=k3s-master

[dns]
k3s-master ansible_host=${master_ip} hostname=k3s-master
