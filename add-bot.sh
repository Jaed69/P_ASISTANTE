#!/usr/bin/env bash
# add-bot.sh — Agrega un nuevo bot al fleet
# Uso: ./add-bot.sh <nombre> [telegram_token] [modelo]
#
# Ejemplo:
#   ./add-bot.sh coder
#   ./add-bot.sh coder "123456:ABC..." "anthropic/claude-haiku-4-5"
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

NAME="${1:-}"
TELEGRAM="${2:-}"
MODEL="${3:-nvidia/llama-3.3-nemotron-super-49b-v1}"

if [ -z "$NAME" ]; then
  echo "Uso: ./add-bot.sh <nombre> [telegram_token] [modelo]"
  echo ""
  echo "Ejemplo:"
  echo "  ./add-bot.sh coder"
  echo "  ./add-bot.sh coder \"123456:ABCdef\" anthropic/claude-haiku-4-5"
  exit 1
fi

[ ! -f .env ] && { echo "Error: .env no encontrado. Ejecuta ./setup.sh primero."; exit 1; }

set -a; source .env; set +a

# Verificar que el nombre no exista ya
if echo " ${BOTS:-} " | grep -q " ${NAME} "; then
  echo "⚠ El bot '$NAME' ya existe en BOTS. Edita .env directamente si quieres cambiarlo."
  exit 1
fi

# Agregar al listado BOTS
if grep -q "^BOTS=" .env; then
  CURRENT=$(grep "^BOTS=" .env | sed 's/^BOTS=//' | tr -d '"')
  sed -i "s|^BOTS=.*|BOTS=\"${CURRENT} ${NAME}\"|" .env
else
  echo "BOTS=\"${NAME}\"" >> .env
fi

# Agregar config del bot
cat >> .env << EOF

# ── Bot: ${NAME} (agregado por add-bot.sh) ──────────────
${NAME}_TELEGRAM_TOKEN=${TELEGRAM}
${NAME}_MODEL=${MODEL}
${NAME}_TOKEN=
EOF

echo "✓ Bot '$NAME' agregado a .env"
echo ""
echo "Próximos pasos:"
echo "  1. Ejecuta ./setup.sh           (crea directorios, genera token, actualiza docker-compose.yml)"
echo "  2. Edita bots/${NAME}/config/SOUL.md   (personalidad del bot)"
echo "  3. docker compose up -d ${NAME}  (levanta solo este bot)"
