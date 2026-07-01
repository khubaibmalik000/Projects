
#!/bin/bash

# =============================
# CONFIGURATION
# =============================
NODE_FILE="nodes_user_07-02-2026.txt"  # file with Node Exporter users and IPs
SSH_USER="deploy"                       # SSH login user
SSH_PASSWORD="CHANGE_ME_SSH_PASSWORD"   # SSH password for SSH_USER
EXPORTER_PASSWORD="CHANGE_ME_EXPORTER_PASSWORD"  # password for Node Exporter authentication

# =============================
# INSTALL LOOP
# =============================
while read -r IP USERNAME; do
  echo ">>> Installing Node Exporter on $IP with Node Exporter user $USERNAME"

  sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no $SSH_USER@$IP "bash -s" <<ENDSSH
set -e

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive
sudo apt update -y
sudo apt install -y curl apache2-utils

# Create Node Exporter system user
id $USERNAME &>/dev/null || sudo useradd -rs /usr/sbin/nologin $USERNAME

# Download Node Exporter
cd /tmp
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar xzf node_exporter-1.7.0.linux-amd64.tar.gz
sudo cp node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
sudo chown $USERNAME:$USERNAME /usr/local/bin/node_exporter

# Create htpasswd authentication
HASH=\$(htpasswd -nb $USERNAME $EXPORTER_PASSWORD | cut -d: -f2)
cat | sudo tee /etc/node_exporter_web.yml >/dev/null <<WEB
basic_auth_users:
  $USERNAME: "\$HASH"
WEB
sudo chown $USERNAME:$USERNAME /etc/node_exporter_web.yml
sudo chmod 600 /etc/node_exporter_web.yml

# Create systemd service
cat | sudo tee /etc/systemd/system/node_exporter.service >/dev/null <<SERVICE
[Unit]
Description=Node Exporter (secured)
After=network.target

[Service]
User=$USERNAME
ExecStart=/usr/local/bin/node_exporter --web.config.file=/etc/node_exporter_web.yml

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl restart node_exporter
ENDSSH

done < "$NODE_FILE"

echo "✅ Node Exporter installation completed on all nodes"
