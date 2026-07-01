# Node Exporter Bulk Installer (SSH loop)

A bash script that installs and secures Prometheus Node Exporter across a list of servers over plain SSH — no Ansible or config management required, just `sshpass` and a heredoc.

## What it does

For each `IP USERNAME` pair listed in a nodes file, it SSHes in and:

1. Installs `curl` and `apache2-utils` (non-interactively).
2. Creates a dedicated, unprivileged system user for running Node Exporter.
3. Downloads and installs the Node Exporter binary to `/usr/local/bin`.
4. Generates an `htpasswd`-hashed Basic Auth credential and writes it to `/etc/node_exporter_web.yml` (permissions locked to `600`).
5. Creates and enables a systemd service that runs Node Exporter with that web-auth config.

## Usage

1. Create a nodes file, one `IP USERNAME` pair per line:

   ```
   10.0.0.11 node_exporter
   10.0.0.12 node_exporter
   10.0.0.13 node_exporter
   ```

2. Edit the `CONFIG` section at the top of the script (`NODE_FILE`, `SSH_USER`, `SSH_PASSWORD`, `EXPORTER_PASSWORD`).

3. Run it:

   ```bash
   chmod +x install_node_exporter.sh
   ./install_node_exporter.sh
   ```

## Requirements

- `sshpass`
- SSH access (password auth) to every target host
- Target hosts: Debian/Ubuntu-based (uses `apt`)

## Note

Credentials in this script are placeholders — set your own `SSH_PASSWORD` and `EXPORTER_PASSWORD` before running. For larger or more dynamic fleets, prefer SSH keys over password auth.
