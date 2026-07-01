# Ansible Node Exporter Installer

A runbook + Ansible playbook for bulk-installing Prometheus Node Exporter across a fleet of servers, secured with HTTP Basic Auth, entirely via `raw` tasks — so it works even on hosts that don't have Python 3 installed yet (a normal Ansible module requires Python on the target).

## What it does

1. **Installs Ansible** and sets up `/etc/ansible`.
2. **Defines an inventory** (`/etc/ansible/hosts`) of worker nodes under a `[workers]` group.
3. **Verifies connectivity** to all hosts, with a fallback `raw`-module ping for hosts without Python 3.
4. **Runs a playbook** that, per host:
   - Downloads and installs the Node Exporter binary.
   - Creates a dedicated, unprivileged `node_exporter` system user.
   - Generates a bcrypt-hashed Basic Auth password with `htpasswd`.
   - Writes Node Exporter's `web.yml` auth config.
   - Creates and enables a systemd service running Node Exporter with that auth config.
5. **Verifies** the service is active and that Basic Auth is enforced (expects HTTP 200 with correct credentials).
6. Includes a **bonus one-liner** for discovering hostnames across raw IPs when you don't yet have Python or SSH keys set up on the targets.

## Usage

```bash
# Test connectivity
ansible all -m ping --ask-pass

# Run the playbook
ansible-playbook -i /etc/ansible/hosts /etc/ansible/playbooks/install_node_exporter_basic_auth.yml \
  -u <ssh_user> -k -b -K

# Verify the service is running
ansible -i /etc/ansible/hosts workers -m raw -a "systemctl is-active node_exporter" -u <ssh_user> -k -b -K

# Verify Basic Auth is enforced (expect HTTP 200)
ansible -i /etc/ansible/hosts workers -m raw -a \
  "curl -s -o /dev/null -w '%{http_code}' -u <inventory_hostname>:<password> http://<ansible_host>:9100/metrics" \
  -u <ssh_user> -k -b -K
```

## Configuration

Edit the inventory (`[workers]` block) and the `basic_auth_plain_password` playbook variable before running. Inventory hostnames/IPs and the auth password in this repo are placeholders — replace with your real fleet details.

## Requirements

- Ansible control node with SSH access to targets
- `sshpass` (for password-based SSH auth) if not using SSH keys
- `apache2-utils` on targets (installed automatically by the playbook, for `htpasswd`)
