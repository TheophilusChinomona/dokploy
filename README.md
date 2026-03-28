<div align="center">
  <a href="https://dokploy.com">
    <img src=".github/sponsors/logo.png" alt="Dokploy - Open Source Alternative to Vercel, Heroku and Netlify." width="100%"  />
  </a>
</div>
<br />

> **This is a personal fork of [Dokploy v0.28.8](https://github.com/Dokploy/dokploy).**
> It ships bug fixes for single-node Docker Swarm + Cloudflare Tunnel setups, plus a
> custom install script for VPS providers (like Hostinger) that don't offer one-click Dokploy.
>
> Upstream project: [dokploy/dokploy](https://github.com/Dokploy/dokploy) — all credit for the
> core platform belongs to the Dokploy team.

---

## What this fork adds

### Bug fixes baked into the image

| Fix | What it solves |
|-----|---------------|
| **Docker Swarm dnsrr** | Postgres and Redis now use `--endpoint-mode dnsrr` instead of VIP. Fixes database connection failures on fresh single-node installs. |
| **Traefik bridge network** | Traefik container is connected to both `dokploy-network` and `bridge` after creation. Fixes routing failures after Traefik recreates. |
| **Empty env file path doubling** | `createEnvFile: true` on an app with no env vars no longer produces a doubled path in the Docker COPY instruction. |
| **Cloudflare Tunnel domain mode** | New `cloudflare-tunnel` certificate type. Routes are HTTP-only (no websecure entrypoint, no redirect-to-https) — required when Cloudflare terminates TLS at the edge. |
| **Node.js healthcheck** | Replaced the `curl`-spawning HEALTHCHECK with a Node.js `http.get()` one-liner. Eliminates the memory regression (~350 MB → 630 MB) introduced by repeated curl subprocesses. |
| **Production env defaults** | `PORT=3000` and `NODE_ENV=production` are set in `.env.production` so the container starts without needing those injected externally. |

### Custom install script

Deploy the full Dokploy stack (Traefik + Postgres + Redis + Dokploy) on any fresh Ubuntu/Debian/RHEL/Arch/Alpine VPS in one command:

```bash
curl -fsSL https://raw.githubusercontent.com/TheophilusChinomona/dokploy/staging/install.sh | bash
```

The script:
- Detects your OS and installs Docker if needed
- Initialises Docker Swarm and creates the `dokploy-network` overlay
- Writes Traefik config and starts Traefik as a plain container (connected to both `dokploy-network` and `bridge`)
- Generates cryptographically random secrets for Postgres, Redis, and the auth secret and saves them to `/etc/dokploy/.secrets`
- Starts Postgres and Redis as Swarm services with `dnsrr` endpoint mode
- Pulls and starts the Dokploy container with all environment variables wired up
- Idempotent — safe to re-run; skips steps already completed

**After install**, Dokploy is available at `http://<your-server-ip>:3000`.

---

## Quick start (Hostinger / manual VPS)

```bash
# 1. SSH into your VPS as root (or a sudo user)
ssh root@<your-server-ip>

# 2. Run the install script
curl -fsSL https://raw.githubusercontent.com/TheophilusChinomona/dokploy/staging/install.sh | bash

# 3. Open the panel
http://<your-server-ip>:3000
```

Secrets are stored at `/etc/dokploy/.secrets`. Keep this file safe — it contains your database passwords.

---

## Cloudflare Tunnel setup

If you're running behind a Cloudflare Tunnel instead of exposing ports 80/443 directly:

1. In your Cloudflare tunnel ingress rules, point all hostnames to `http://localhost:80` (not `http://dokploy-traefik:80` — cloudflared runs on the host, not inside Docker).

2. When adding a domain to an app in Dokploy, set the **Certificate** field to `Cloudflare Tunnel`. This disables the HTTPS entrypoint and `redirect-to-https` middleware — both of which cause 404s or redirect loops when Cloudflare is terminating TLS for you.

3. Always end your tunnel ingress array with a catch-all:
   ```json
   { "service": "http_status:404" }
   ```

---

## Docker image

```
theophiluschinomona/theochinomona.tech:latest
```

The image is built automatically by GitHub Actions on every push to the `staging` branch.
Tagged as both `:latest` and `:<version>` (e.g. `:v0.28.8`).

---

## Contributing

### Running locally

```bash
git clone https://github.com/TheophilusChinomona/dokploy.git
cd dokploy
pnpm install
pnpm dev
```

You'll need a local Postgres and Redis. Copy `.env.production` to `.env` and fill in your connection strings.

### Branch layout

| Branch | Purpose |
|--------|---------|
| `staging` | Active development — all fixes and new work go here |
| `canary` | Upstream Dokploy main branch — used as the rebase target |

### How to contribute a fix

1. Fork this repo and branch off `staging`
2. Make your change
3. Open a PR targeting `staging`

### Syncing with upstream

When Dokploy ships a new release on `canary`, use the `/sync-upstream` skill (if you're using Claude Code) or run manually:

```bash
git remote add upstream https://github.com/Dokploy/dokploy.git
git fetch upstream canary
git rebase upstream/canary
git push --force-with-lease origin staging
```

**Watch these files** — they contain our patches and must be checked after every rebase:

- `packages/server/src/setup/postgres-setup.ts` — dnsrr endpoint mode
- `packages/server/src/setup/redis-setup.ts` — dnsrr endpoint mode
- `packages/server/src/setup/traefik-setup.ts` — bridge network + chmod
- `packages/server/src/utils/builders/utils.ts` — env path fix
- `packages/server/src/utils/traefik/domain.ts` — cloudflare-tunnel routing
- `packages/server/src/db/schema/shared.ts` + related schema/validation files — cloudflare-tunnel enum
- `Dockerfile` — Node.js healthcheck (must stay as `node -e`, not `curl`)
- `apps/dokploy/drizzle/` — our migration is `0155_cloudflare_tunnel_mode.sql`; renumber if upstream takes that index

### Known issues not yet fixed in this fork

See [`dokploy-issues-handover.md`](dokploy-issues-handover.md) for the full list. Issues still open include:

- Supabase self-hosted stack has networking issues under Docker Swarm (run it with plain `docker compose up -d` instead)
- `dockerfile` field is relative to `dockerContextPath`, not repo root (UI labelling issue)
- Port mismatch causes 502 — the port in Dokploy's domain config must match the container's internal listen port

---

## Original Dokploy

Dokploy is a free, self-hostable Platform as a Service (PaaS) that simplifies the deployment
and management of applications and databases.

- **Applications**: Deploy any type of application (Node.js, PHP, Python, Go, Ruby, etc.).
- **Databases**: MySQL, PostgreSQL, MongoDB, MariaDB, libsql, Redis.
- **Backups**: Automate backups to external storage.
- **Docker Compose**: Native support for complex multi-service apps.
- **Multi Node**: Scale with Docker Swarm.
- **Traefik Integration**: Automatic routing and load balancing.
- **Real-time Monitoring**: CPU, memory, storage, network.
- **Notifications**: Slack, Discord, Telegram, Email, and more.

Full docs: [docs.dokploy.com](https://docs.dokploy.com) | Upstream repo: [dokploy/dokploy](https://github.com/Dokploy/dokploy)
