# LMS — Docker Deployment Guide

## Quick-start

### 1. Clone & configure
```bash
# Copy the example env file and fill in your secrets
cp .env.example .env
nano .env   # or use any editor
```

### 2. Build images
```bash
docker compose build
```

### 3. Start the stack
```bash
docker compose up -d
```

The stack starts in dependency order:
`postgres` (healthy) → `backend` (migrations run, then healthy) → `frontend` → `cloudflared`

### 4. Stop the stack
```bash
docker compose down
```

### 5. View logs
```bash
# All services
docker compose logs -f

# Single service
docker compose logs -f backend
docker compose logs -f frontend
docker compose logs -f cloudflared
docker compose logs -f postgres
```

### 6. Check health status
```bash
docker compose ps
```

### 7. Update (pull latest code, rebuild, redeploy)
```bash
git pull
docker compose build --no-cache
docker compose up -d
```

---

## Database

### Run Prisma migrations manually
```bash
docker compose exec backend npx prisma migrate deploy --config prisma.config.ts
```

### Run Prisma Studio (GUI — exposes on host port 5555)
```bash
docker compose exec backend npx prisma studio --config prisma.config.ts
```

### Run any one-off Prisma command
```bash
docker compose exec backend npx prisma <command> --config prisma.config.ts
```

### Backup the database
```bash
# Creates a compressed SQL dump in the current directory
docker compose exec postgres pg_dump -U $POSTGRES_USER $POSTGRES_DB | gzip > lms_backup_$(date +%Y%m%d_%H%M%S).sql.gz
```

### Restore the database
```bash
# Restore from a dump file (replace <file> with your .sql.gz path)
gunzip -c <file>.sql.gz | docker compose exec -T postgres psql -U $POSTGRES_USER $POSTGRES_DB
```

---

## Cloudflare Tunnel setup

### Step 1 — Create the tunnel

1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Navigate to **Networks → Tunnels**
3. Click **Create a tunnel**
4. Choose **Cloudflared** as the connector type
5. Give it a name (e.g. `lms-tunnel`)
6. Click **Next**

### Step 2 — Copy the tunnel token

On the "Install and run a connector" screen:
- Select **Docker** as the environment
- You will see a `docker run` command containing `--token <LONG_TOKEN_STRING>`
- **Copy that token string only** (not the full docker command)
- Paste it as `TUNNEL_TOKEN` in your `.env` file

### Step 3 — Add a public hostname

1. After saving the connector, click **Next** or go to **Public Hostnames**
2. Click **Add a public hostname**
3. Fill in:
   - **Subdomain**: (leave blank for root, or use `www`)
   - **Domain**: your domain (must already be on Cloudflare)
   - **Type**: `HTTP`
   - **URL**: `frontend:80`
4. Click **Save hostname**

### Step 4 — Confirm the tunnel is connected

```bash
# cloudflared logs should show:
docker compose logs cloudflared
# Look for: "Connection ... registered"  or  "Registered tunnel connection"

# Also check in the dashboard — the tunnel dot should be green (Healthy)
```

---

## Security checklist

| Item | Action |
|------|--------|
| Database port | Not exposed to host (no `ports:` on postgres service) |
| Backend port | Not exposed to host (no `ports:` on backend service) |
| JWT secret | Generate with `openssl rand -hex 64` — minimum 64 chars |
| HTTPS | Cloudflare provides free TLS termination automatically |
| Bot protection | Enable **Bot Fight Mode** in Cloudflare dashboard → Security → Bots |
| DDoS | Cloudflare free plan includes automatic DDoS mitigation |
| Image updates | Run `docker compose pull && docker compose build --no-cache && docker compose up -d` monthly |
| .env file | Never commit `.env` to git — it's in `.gitignore` |

---

## Architecture

```
Internet
  │
  ▼
Cloudflare Edge (TLS, DDoS, Bot protection)
  │
  ▼
cloudflared container (tunnel)
  │  reaches out to Cloudflare — no inbound ports needed
  ▼
frontend container :80 (Nginx)
  ├── /          → serves React SPA (dist/)
  ├── /api/*     → proxy_pass → backend:3000
  └── assets/*   → cached 1 year (hashed filenames)
        │
        ▼
backend container :3000 (Express)
  │  runs prisma migrate deploy on startup
  ▼
postgres container :5432
  └── named volume: postgres-data
```

---

## Testing checklist

### 1. Build and start locally
```bash
docker compose build
docker compose up -d
docker compose ps   # all services should be "Up (healthy)"
```

### 2. Test from another device on your local network
Open a browser on another device and navigate to:
```
http://<server-local-ip>:8080
```
Replace `<server-local-ip>` with your Ubuntu server's local IP (e.g. `192.168.1.100`).
Find it with: `ip addr show` on the server.

### 3. Check logs and health
```bash
docker compose logs -f
docker compose ps
```

### 4. Test through Cloudflare Tunnel
- Complete the Cloudflare Tunnel setup above
- Start the stack: `docker compose up -d`
- Wait for `docker compose logs cloudflared` to show "Registered tunnel connection"
- Open `https://yourdomain.com` in a browser
- Test login, file upload, AI features, and code execution

### 5. Test auto-restart after reboot
```bash
# On the Ubuntu server:
sudo reboot
# After reboot, wait ~60 seconds then:
docker compose -f /path/to/docker-compose.yml ps
# All services should be Up and healthy automatically
```
> All services have `restart: unless-stopped`, so Docker will restart them automatically after the server reboots — as long as the Docker daemon itself is set to start on boot (it is by default on Ubuntu).
