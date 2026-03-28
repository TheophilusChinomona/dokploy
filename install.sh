#!/bin/bash
set -e

# ============================================================
# Dokploy Custom Fork Installer
# Image: theophiluschinomona/theochinomona.tech:latest
# Usage: curl -fsSL https://raw.githubusercontent.com/TheophilusChinomona/dokploy/staging/install.sh | bash
# ============================================================

DOKPLOY_IMAGE="theophiluschinomona/theochinomona.tech:latest"
TRAEFIK_VERSION="3.6.7"
POSTGRES_VERSION="16"
REDIS_VERSION="7-alpine"
DOKPLOY_PORT="3000"
TRAEFIK_PORT="80"
TRAEFIK_SSL_PORT="443"
BASE_DIR="/etc/dokploy"
TRAEFIK_DIR="$BASE_DIR/traefik"
DYNAMIC_DIR="$TRAEFIK_DIR/dynamic"

# ── Colour helpers ──────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
info() { echo -e "${YELLOW}→  $*${NC}"; }
fail() { echo -e "${RED}❌ $*${NC}"; exit 1; }

# ── Root / sudo detection ───────────────────────────────────
if [ "$EUID" -eq 0 ]; then
    SUDO=""
else
    command -v sudo >/dev/null 2>&1 || fail "sudo is required for non-root installs"
    sudo -n true 2>/dev/null || fail "Passwordless sudo is required. Run: echo '$USER ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/$USER"
    SUDO="sudo"
fi

# ── OS detection ────────────────────────────────────────────
OS_TYPE=$(grep -w "ID" /etc/os-release | cut -d= -f2 | tr -d '"')
case "$OS_TYPE" in
    ubuntu|debian|raspbian|pop|linuxmint|zorin) FAMILY="debian" ;;
    centos|fedora|rhel|ol|rocky|almalinux)      FAMILY="rhel"   ;;
    arch|manjaro)                                FAMILY="arch"   ;;
    alpine)                                      FAMILY="alpine" ;;
    *) fail "Unsupported OS: $OS_TYPE. Supported: Ubuntu/Debian, RHEL/Fedora, Arch, Alpine" ;;
esac

echo ""
echo "============================================================"
echo "  Dokploy Custom Fork Installer"
echo "  OS: $OS_TYPE ($FAMILY)  |  Image: $DOKPLOY_IMAGE"
echo "============================================================"
echo ""

# ── Step 1: Install utilities ───────────────────────────────
info "1. Installing utilities (curl, wget, jq, openssl)..."
case "$FAMILY" in
    debian)
        export DEBIAN_FRONTEND=noninteractive
        $SUDO apt-get update -y -qq
        $SUDO apt-get install -y -qq curl wget git jq openssl unzip >/dev/null
        ;;
    rhel)
        $SUDO dnf install -y curl wget git jq openssl unzip >/dev/null 2>&1
        ;;
    arch)
        $SUDO pacman -Sy --noconfirm --needed curl wget git jq openssl >/dev/null
        ;;
    alpine)
        $SUDO apk update >/dev/null
        $SUDO apk add curl wget git jq openssl unzip >/dev/null
        ;;
esac
ok "Utilities installed"

# ── Step 2: Check ports ─────────────────────────────────────
info "2. Checking ports 80 and 443..."
if ss -tulnp 2>/dev/null | grep -q ':80 '; then
    echo -e "${YELLOW}   Warning: something is already on port 80${NC}"
fi
if ss -tulnp 2>/dev/null | grep -q ':443 '; then
    echo -e "${YELLOW}   Warning: something is already on port 443${NC}"
fi
ok "Port check done"

# ── Step 3: Install Docker ──────────────────────────────────
info "3. Installing Docker..."
if command -v docker >/dev/null 2>&1; then
    ok "Docker already installed ($(docker --version | awk '{print $3}' | tr -d ','))"
else
    case "$FAMILY" in
        alpine)
            $SUDO apk add docker docker-cli-compose >/dev/null
            $SUDO rc-update add docker default >/dev/null 2>&1
            $SUDO service docker start >/dev/null 2>&1
            ;;
        arch)
            $SUDO pacman -Sy docker docker-compose --noconfirm >/dev/null
            $SUDO systemctl enable --now docker >/dev/null 2>&1
            ;;
        *)
            curl -fsSL https://get.docker.com | $SUDO sh >/dev/null 2>&1
            command -v docker >/dev/null 2>&1 || fail "Docker installation failed. Install manually: https://docs.docker.com/engine/install/"
            ;;
    esac
    ok "Docker installed"
fi

# Add current user to docker group
if [ -n "$SUDO" ] && ! groups "$USER" | grep -qw docker; then
    $SUDO usermod -aG docker "$USER"
    info "Added $USER to docker group (re-login may be needed for non-sudo docker commands)"
fi

# ── Step 4: Install rclone ──────────────────────────────────
info "4. Installing rclone (for backups)..."
if command -v rclone >/dev/null 2>&1; then
    ok "rclone already installed"
else
    curl -fsSL https://rclone.org/install.sh | $SUDO bash >/dev/null 2>&1
    ok "rclone installed"
fi

# ── Step 5: Docker Swarm ────────────────────────────────────
info "5. Initialising Docker Swarm..."
if docker info 2>/dev/null | grep -q "Swarm: active"; then
    ok "Swarm already active"
else
    ADVERTISE_ADDR="${ADVERTISE_ADDR:-}"
    if [ -z "$ADVERTISE_ADDR" ]; then
        ADVERTISE_ADDR=$(curl -4s --connect-timeout 5 https://ifconfig.io 2>/dev/null \
            || curl -4s --connect-timeout 5 https://icanhazip.com 2>/dev/null \
            || curl -4s --connect-timeout 5 https://ipecho.net/plain 2>/dev/null)
    fi
    [ -z "$ADVERTISE_ADDR" ] && fail "Could not detect server IP. Set ADVERTISE_ADDR=<ip> and re-run."
    docker swarm init --advertise-addr "$ADVERTISE_ADDR"
    ok "Swarm initialised (advertise addr: $ADVERTISE_ADDR)"
fi

# ── Step 6: Overlay network ─────────────────────────────────
info "6. Creating dokploy-network..."
if docker network ls | grep -q "dokploy-network"; then
    ok "dokploy-network already exists"
else
    docker network create --driver overlay --attachable dokploy-network
    ok "dokploy-network created"
fi

# ── Step 7: Directories ─────────────────────────────────────
info "7. Creating directories..."
$SUDO mkdir -p \
    "$DYNAMIC_DIR" \
    "$BASE_DIR/ssh" \
    "$BASE_DIR/logs" \
    "$BASE_DIR/applications" \
    "$BASE_DIR/compose" \
    "$BASE_DIR/certificates" \
    "$BASE_DIR/monitoring" \
    "$BASE_DIR/registry" \
    "$BASE_DIR/schedules" \
    "$BASE_DIR/volume-backups"
$SUDO chmod 700 "$BASE_DIR/ssh"
[ -n "$SUDO" ] && $SUDO chown -R "$USER:$USER" "$BASE_DIR" 2>/dev/null || true
ok "Directories ready"

# ── Step 8: Traefik config ──────────────────────────────────
info "8. Writing Traefik config..."
if [ ! -f "$TRAEFIK_DIR/traefik.yml" ]; then
    cat > "$TRAEFIK_DIR/traefik.yml" <<'TRAEFIK_YML'
providers:
  swarm:
    exposedByDefault: false
    watch: true
  docker:
    exposedByDefault: false
    watch: true
    network: dokploy-network
  file:
    directory: /etc/dokploy/traefik/dynamic
    watch: true
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"
    http3:
      advertisedPort: 443
    http:
      tls:
        certResolver: letsencrypt
api:
  insecure: true
certificatesResolvers:
  letsencrypt:
    acme:
      email: test@localhost.com
      storage: /etc/dokploy/traefik/dynamic/acme.json
      httpChallenge:
        entryPoint: web
TRAEFIK_YML
    ok "traefik.yml written"
else
    ok "traefik.yml already exists"
fi

if [ ! -f "$DYNAMIC_DIR/middlewares.yml" ]; then
    cat > "$DYNAMIC_DIR/middlewares.yml" <<'MIDDLEWARES_YML'
http:
  middlewares:
    redirect-to-https:
      redirectScheme:
        scheme: https
        permanent: true
MIDDLEWARES_YML
    chmod 644 "$DYNAMIC_DIR/middlewares.yml"
    ok "middlewares.yml written"
else
    ok "middlewares.yml already exists"
fi

if [ -f "$DYNAMIC_DIR/acme.json" ]; then
    chmod 600 "$DYNAMIC_DIR/acme.json"
fi

# ── Step 9: Traefik container ───────────────────────────────
info "9. Starting Traefik..."
if docker inspect dokploy-traefik >/dev/null 2>&1; then
    ok "Traefik already running"
else
    # Remove legacy swarm service if present
    if docker service inspect dokploy-traefik >/dev/null 2>&1; then
        info "Removing legacy Traefik swarm service..."
        docker service rm dokploy-traefik
        sleep 8
    fi

    docker pull "traefik:v${TRAEFIK_VERSION}"
    docker run -d \
        --name dokploy-traefik \
        --restart always \
        --network dokploy-network \
        -v "$TRAEFIK_DIR/traefik.yml:/etc/traefik/traefik.yml" \
        -v "$DYNAMIC_DIR:/etc/dokploy/traefik/dynamic" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -p "${TRAEFIK_PORT}:${TRAEFIK_PORT}" \
        -p "${TRAEFIK_SSL_PORT}:${TRAEFIK_SSL_PORT}" \
        -p "${TRAEFIK_SSL_PORT}:${TRAEFIK_SSL_PORT}/udp" \
        "traefik:v${TRAEFIK_VERSION}"

    # Also connect to bridge so Traefik can reach plain containers
    docker network connect bridge dokploy-traefik 2>/dev/null || true
    ok "Traefik v${TRAEFIK_VERSION} started"
fi

# ── Step 10: Generate secrets ───────────────────────────────
info "10. Generating secrets..."
SECRETS_FILE="$BASE_DIR/.secrets"
if [ -f "$SECRETS_FILE" ]; then
    # shellcheck disable=SC1090
    source "$SECRETS_FILE"
    ok "Loaded existing secrets"
else
    POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)
    REDIS_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)
    BETTER_AUTH_SECRET=$(openssl rand -base64 32)
    cat > "$SECRETS_FILE" <<EOF
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
REDIS_PASSWORD=$REDIS_PASSWORD
BETTER_AUTH_SECRET=$BETTER_AUTH_SECRET
EOF
    chmod 600 "$SECRETS_FILE"
    ok "Secrets generated and saved to $SECRETS_FILE"
fi

# ── Step 11: Postgres ───────────────────────────────────────
info "11. Starting Postgres..."
if docker service inspect dokploy-postgres >/dev/null 2>&1; then
    ok "Postgres service already exists"
else
    docker service create \
        --name dokploy-postgres \
        --network dokploy-network \
        --endpoint-mode dnsrr \
        --env "POSTGRES_USER=dokploy" \
        --env "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" \
        --env "POSTGRES_DB=dokploy" \
        --mount type=volume,source=dokploy-postgres-data,target=/var/lib/postgresql/data \
        "postgres:${POSTGRES_VERSION}"
    ok "Postgres started"
fi

# ── Step 12: Redis ──────────────────────────────────────────
info "12. Starting Redis..."
if docker service inspect dokploy-redis >/dev/null 2>&1; then
    ok "Redis service already exists"
else
    docker service create \
        --name dokploy-redis \
        --network dokploy-network \
        --endpoint-mode dnsrr \
        --mount type=volume,source=dokploy-redis-data,target=/data \
        "redis:${REDIS_VERSION}" \
        redis-server --requirepass "${REDIS_PASSWORD}"
    ok "Redis started"
fi

# Give services a moment to start before Dokploy connects
info "    Waiting for Postgres and Redis to be ready..."
sleep 8

# ── Step 13: Dokploy ────────────────────────────────────────
info "13. Starting Dokploy..."
if docker inspect dokploy >/dev/null 2>&1; then
    ok "Dokploy already running"
else
    docker pull "$DOKPLOY_IMAGE"
    docker run -d \
        --name dokploy \
        --restart always \
        --network dokploy-network \
        -e NODE_ENV=production \
        -e PORT="${DOKPLOY_PORT}" \
        -e DATABASE_URL="postgresql://dokploy:${POSTGRES_PASSWORD}@dokploy-postgres:5432/dokploy" \
        -e REDIS_URL="redis://:${REDIS_PASSWORD}@dokploy-redis:6379" \
        -e BETTER_AUTH_SECRET="${BETTER_AUTH_SECRET}" \
        -p "${DOKPLOY_PORT}:${DOKPLOY_PORT}" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "$BASE_DIR:$BASE_DIR" \
        "$DOKPLOY_IMAGE"
    ok "Dokploy started"
fi

# ── Done ─────────────────────────────────────────────────────
echo ""
echo "============================================================"
ok "Installation complete!"
echo ""
echo "  Dokploy UI → http://$(curl -4s --connect-timeout 3 https://ifconfig.io 2>/dev/null || echo '<your-server-ip>'):${DOKPLOY_PORT}"
echo ""
echo "  Secrets stored at: $SECRETS_FILE"
echo "  Traefik config:    $TRAEFIK_DIR/"
echo "============================================================"
echo ""
