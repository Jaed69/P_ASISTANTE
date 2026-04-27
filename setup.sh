#!/usr/bin/env bash
# setup.sh — Inicializa todos los bots y genera docker-compose.yml + nginx.conf
# Uso: ./setup.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; exit 1; }
step()  { echo -e "\n${CYAN}──${NC} $*"; }

# ── .env ─────────────────────────────────────────────────────────────────────
if [ ! -f .env ]; then
  cp .env.example .env
  warn ".env no encontrado → copiado desde .env.example"
  warn "Edita .env con tu OPENROUTER_API_KEY y los TELEGRAM_TOKEN de cada bot."
  warn "Luego vuelve a ejecutar: ./setup.sh"
  exit 0
fi

set -a
source .env
set +a

[ -z "${OPENROUTER_API_KEY:-}" ]  && error "OPENROUTER_API_KEY no configurado en .env"
[[ "${OPENROUTER_API_KEY:-}" == *"CHANGE_ME"* ]] && error "OPENROUTER_API_KEY aún tiene el valor de ejemplo — cámbialo en .env"
[ -z "${BOTS:-}" ] && error "BOTS no configurado en .env"
[ -z "${DB_ENCRYPTION_KEY:-}" ] && error "DB_ENCRYPTION_KEY no configurado en .env"

# ── Detectar runtime seguro ──────────────────────────────────────────────────
if [ -x ./scripts/test-gvisor.sh ]; then
  step "Detectando runtime seguro (gVisor o fallback)"
  ./scripts/test-gvisor.sh
else
  warn "scripts/test-gvisor.sh no encontrado — asumiendo runc sin restricciones"
fi

if [ -f runtime.env ]; then
  set -a
  source runtime.env
  set +a
  info "Runtime detectado: ${FLEET_RUNTIME:-runc}"
fi

# ── Inicializar fleet.db si no existe ────────────────────────────────────────
if [ ! -f data/fleet.db ]; then
  step "Inicializando fleet.db"
  if command -v python3 &>/dev/null; then
    python3 scripts/db_init.py
    info "fleet.db creado"
  else
    warn "python3 no encontrado — saltando inicialización de fleet.db"
    warn "Ejecutá manualmente: python3 scripts/db_init.py"
  fi
else
  info "fleet.db ya existe"
fi

# ── Generar token seguro ──────────────────────────────────────────────────────
gen_token() {
  # dd reads exactly 32 bytes → no SIGPIPE. Works on Linux, NixOS, VPS.
  dd if=/dev/urandom bs=32 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n'
}

# ── Configurar cada bot ───────────────────────────────────────────────────────
for BOT in $BOTS; do
  step "Bot: $BOT"

  TOKEN_VAR="${BOT}_TOKEN";       TOKEN="${!TOKEN_VAR:-}"
  TELEGRAM_VAR="${BOT}_TELEGRAM_TOKEN"; TELEGRAM="${!TELEGRAM_VAR:-}"
  MODEL_VAR="${BOT}_MODEL";       MODEL="${!MODEL_VAR:-nvidia/llama-3.3-nemotron-super-49b-v1}"

  # Generar token si no existe
  if [ -z "$TOKEN" ]; then
    TOKEN=$(gen_token)
    if grep -q "^${TOKEN_VAR}=" .env; then
      sed -i "s|^${TOKEN_VAR}=.*|${TOKEN_VAR}=${TOKEN}|" .env
    else
      echo "${TOKEN_VAR}=${TOKEN}" >> .env
    fi
    info "Token generado para '$BOT' (guardado en .env)"
  fi

  # Directorios
  mkdir -p "bots/$BOT/config/agents/main/agent"
  mkdir -p "bots/$BOT/workspace"
  mkdir -p "bots/$BOT/data"
  mkdir -p "bots/$BOT/skills"

  # openclaw.json — siempre se regenera (para actualizar modelo y rutas)
  cat > "bots/$BOT/config/openclaw.json" << EOF
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "controlUi": {
      "allowedOrigins": [
        "http://localhost:18788",
        "http://127.0.0.1:18788"
      ]
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "openrouter/${MODEL}"
      }
    }
  }
}
EOF
  info "openclaw.json → modelo $MODEL"

  # models.json — no sobreescribir si ya fue personalizado
  if [ ! -f "bots/$BOT/config/agents/main/agent/models.json" ]; then
    cp templates/models.json "bots/$BOT/config/agents/main/agent/models.json"
    info "models.json copiado desde template"
  else
    info "models.json ya existe → no sobreescrito"
  fi

  # SOUL.md — no sobreescribir si ya fue personalizado
  if [ ! -f "bots/$BOT/config/SOUL.md" ]; then
    sed "s/__BOT_NAME__/${BOT}/g" templates/SOUL.md > "bots/$BOT/config/SOUL.md"
    info "SOUL.md creado → edítalo en bots/$BOT/config/SOUL.md"
  else
    info "SOUL.md ya existe → no sobreescrito"
  fi

  [ -z "$TELEGRAM" ] && warn "TELEGRAM_TOKEN vacío para '$BOT' — el bot de Telegram no funcionará hasta que lo configures"
done

# Re-cargar .env para que los tokens recién generados estén disponibles
set -a
source .env
set +a

# ── Generar nginx.conf ───────────────────────────────────────────────────────
step "Generando nginx.conf"

cat > nginx.conf << 'HEADER'
# AUTO-GENERADO por setup.sh — NO edites este archivo manualmente.
# Para hacer cambios: edita .env o bots/<nombre>/config/ y re-ejecuta ./setup.sh

server {
  listen 80;
  server_name _;

HEADER

for BOT in $BOTS; do
  cat >> nginx.conf << EOF
  location /${BOT}/ {
    proxy_pass http://${BOT}:18789/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }

EOF
done

cat >> nginx.conf << 'FOOTER'
  # Panel admin (Fase 4)
  # location /admin/ {
  #   proxy_pass http://panel:3000/;
  # }
}
FOOTER

info "nginx.conf generado"

# ── Generar docker-compose.yml ────────────────────────────────────────────────
step "Generando docker-compose.yml"

cat > docker-compose.yml << 'HEADER'
# AUTO-GENERADO por setup.sh — NO edites este archivo manualmente.
# Para hacer cambios: edita .env o bots/<nombre>/config/ y re-ejecuta ./setup.sh

services:
HEADER

for BOT in $BOTS; do
  TOKEN_VAR="${BOT}_TOKEN"; TOKEN="${!TOKEN_VAR:-}"

  cat >> docker-compose.yml << EOF

  # ── ${BOT} ── UI: http://127.0.0.1:18788/${BOT}/ ── SOUL: bots/${BOT}/config/SOUL.md
  ${BOT}:
    image: \${OPENCLAW_IMAGE:-ghcr.io/openclaw/openclaw:2026.4.15}
    container_name: openclaw-${BOT}
    restart: unless-stopped
    stop_grace_period: 30s
    stop_signal: SIGTERM
    entrypoint: ["/entrypoint.sh"]
    environment:
      - OPENCLAW_GATEWAY_TOKEN=${TOKEN}
      - OPENROUTER_API_KEY=\${OPENROUTER_API_KEY}
      - TELEGRAM_BOT_TOKEN=\${${BOT}_TELEGRAM_TOKEN:-}
      - TZ=\${TZ:-America/Lima}
      - HOME=/home/node
      - TERM=xterm-256color
    volumes:
      - ./bots/${BOT}/config:/home/node/.openclaw/config
      - ./bots/${BOT}/workspace:/home/node/.openclaw/workspace
      - ./bots/${BOT}/data:/home/node/.openclaw/data
      - ./bots/${BOT}/skills:/home/node/.openclaw/skills
      - ./scripts/entrypoint.sh:/entrypoint.sh:ro
    dns:
      - 8.8.8.8
      - 1.1.1.1
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost:18789/healthz"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 90s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    tmpfs:
      - /tmp
EOF

  # Runtime y seguridad (inyectado por test-gvisor.sh)
  if [ "${FLEET_RUNTIME:-}" = "runsc" ]; then
    cat >> docker-compose.yml << EOF
    runtime: runsc
EOF
  fi

  if [ -n "${FLEET_SECURITY_OPT:-}" ]; then
    echo "    security_opt:" >> docker-compose.yml
    IFS=',' read -ra SEC_OPTS <<< "$FLEET_SECURITY_OPT"
    for opt in "${SEC_OPTS[@]}"; do
      echo "      - $opt" >> docker-compose.yml
    done
  fi

  if [ -n "${FLEET_CAP_DROP:-}" ]; then
    echo "    cap_drop:" >> docker-compose.yml
    IFS=',' read -ra CAPS <<< "$FLEET_CAP_DROP"
    for cap in "${CAPS[@]}"; do
      echo "      - $cap" >> docker-compose.yml
    done
  fi

  if [ -n "${FLEET_CAP_ADD:-}" ]; then
    echo "    cap_add:" >> docker-compose.yml
    IFS=',' read -ra CAPS <<< "$FLEET_CAP_ADD"
    for cap in "${CAPS[@]}"; do
      echo "      - $cap" >> docker-compose.yml
    done
  fi
done

cat >> docker-compose.yml << 'NGINX'

  # ── nginx ── Puerto único expuesto al host: 127.0.0.1:18788
  nginx:
    image: nginx:1.25-alpine
    container_name: openclaw-nginx
    restart: unless-stopped
    ports:
      - "127.0.0.1:18788:80"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
NGINX

for BOT in $BOTS; do
  cat >> docker-compose.yml << EOF
      - ${BOT}
EOF
done

info "docker-compose.yml generado"

# ── Resumen ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Setup completo${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo ""
echo "  Bots configurados:"
for BOT in $BOTS; do
  TELEGRAM_VAR="${BOT}_TELEGRAM_TOKEN"; TELEGRAM="${!TELEGRAM_VAR:-}"
  SOUL="bots/$BOT/config/SOUL.md"
  TELEGRAM_STATUS="${TELEGRAM:+✓ Telegram OK}"
  TELEGRAM_STATUS="${TELEGRAM_STATUS:-⚠ sin Telegram}"
  echo "    • $BOT → http://127.0.0.1:18788/${BOT}/ | $TELEGRAM_STATUS | personalidad: $SOUL"
done
echo ""
echo "  Comandos:"
echo "    docker compose up -d             # levantar todo"
echo "    docker compose ps                # estado"
echo "    docker compose logs -f <nombre>  # logs de un bot"
echo "    docker compose restart <nombre>  # reiniciar tras editar SOUL.md"
echo ""
echo "  Para agregar un bot:"
echo "    ./add-bot.sh <nombre> [telegram_token] [modelo]"
echo ""
