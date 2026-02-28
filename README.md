# my_n8n

Automated n8n deployment with Nginx, PostgreSQL, and Let's Encrypt via Docker Compose.

## Stack

- **n8n** — workflow automation engine
- **PostgreSQL 15** — persistent database
- **Nginx** — HTTPS reverse proxy
- **Certbot** — Let's Encrypt SSL certificates

## Prerequisites

- Docker & Docker Compose
- A domain pointing to your server
- Ports 80 and 443 open

## Installation

```bash
git clone <repo> my_n8n
cd my_n8n
bash install.sh
```

The script will:
1. Ask for your domain and persist it in `.bashrc`
2. Generate `nginx/nginx.conf` from the template
3. Create a dummy certificate, start Nginx, then obtain the real Let's Encrypt certificate
4. Reload Nginx with the valid certificate

## Start / Stop

```bash
docker compose up -d      # start
docker compose down       # stop
docker compose logs -f    # follow logs
```

## Configuration

| Variable | Description |
|---|---|
| `DOMAIN` | Your domain (e.g. `n8n.example.com`) |
| `DB_POSTGRESDB_PASSWORD` | PostgreSQL password (change in production) |

> n8n and PostgreSQL data are persisted in Docker volumes (`n8n_data`, `db_data`).
