# RustDesk Server (Docker Compose)

A self-hosted [RustDesk](https://rustdesk.com/) remote-desktop server, deployed via Docker Compose. Runs the open-source ID/rendezvous server (`hbbs`), relay server (`hbbr`), and a web admin console + REST API (`rustdesk-api`) for managing users and devices.

## Components

| Service | Image | Role |
|---|---|---|
| `hbbs` | `rustdesk/rustdesk-server` | ID/rendezvous server — handles client registration and NAT traversal (ports `21115`, `21116/tcp+udp`, `21118`). |
| `hbbr` | `rustdesk/rustdesk-server` | Relay server — relays traffic between peers when a direct P2P connection isn't possible (ports `21117`, `21119`). |
| `rustdesk-api` | `lejianwen/rustdesk-api` | Web admin console + REST API on top of `hbbs`/`hbbr`, for login, address book, and device management (port `21114`). |

## Usage

```bash
docker compose up -d
```

On first boot, `hbbs` generates a keypair (`id_ed25519` / `id_ed25519.pub`) under `./data` — this is the server's identity key and **must be backed up**; losing it breaks every already-paired client.

Set `RUSTDESK_API_RUSTDESK_API_SERVER` and `RUSTDESK_API_RUSTDESK_KEY` in the compose file to your server's reachable address and its public key (printed in the `hbbs` container logs / saved in `./data/id_ed25519.pub`).

## Client configuration

In the RustDesk client, under **Settings → Network**:

- **ID server**: `<your-server-ip>:21116`
- **Relay server**: `<your-server-ip>:21117`
- **API server**: `http://<your-server-ip>:21114` (optional — only needed for login/address-book/device-management via `rustdesk-api`)
- **Key**: the server's public key from `./data/id_ed25519.pub`

Note: the ID/Relay server fields take a bare `host:port`, not a URL — only the API server field takes `http://`.

## Persistent data

- `./data` — `hbbs`/`hbbr` state: the keypair and SQLite DB of registered clients.
- `./data-api` — `rustdesk-api`'s own SQLite DB (users, admin console).

Both directories should be backed up; neither is included in this repo since they contain host-specific keys/data.

## Requirements

- Docker + Docker Compose
- Ports `21114-21119` reachable from clients (21116 needs both TCP and UDP for NAT traversal)
