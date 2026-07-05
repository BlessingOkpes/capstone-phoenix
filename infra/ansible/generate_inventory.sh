#!/bin/bash
# Run this from the control EC2 instance AFTER `terraform apply` succeeds.
# Reads Terraform outputs and writes an Ansible inventory file.
set -e

TF_DIR="../terraform"
KEY_PATH=$(terraform -chdir="$TF_DIR" output -raw ssh_private_key_path)

SERVER_IP=$(terraform -chdir="$TF_DIR" output -raw server_public_ip)
SERVER_PRIVATE_IP=$(terraform -chdir="$TF_DIR" output -raw server_private_ip)
AGENT_IPS=$(terraform -chdir="$TF_DIR" output -json agent_public_ips | tr -d '[]," ' | tr '\n' ' ')

cat > inventory.ini <<EOF
[k3s_server]
server ansible_host=${SERVER_IP} ansible_user=ubuntu ansible_ssh_private_key_file=${KEY_PATH} server_private_ip=${SERVER_PRIVATE_IP}

[k3s_agents]
EOF

i=1
for ip in $AGENT_IPS; do
  echo "agent${i} ansible_host=${ip} ansible_user=ubuntu ansible_ssh_private_key_file=${KEY_PATH}" >> inventory.ini
  i=$((i+1))
done

cat >> inventory.ini <<EOF

[k3s_cluster:children]
k3s_server
k3s_agents

[k3s_cluster:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

echo "Inventory written to inventory.ini:"
cat inventory.ini
echo ""
echo "Your nip.io domain will be: taskapp.${SERVER_IP}.nip.io"
