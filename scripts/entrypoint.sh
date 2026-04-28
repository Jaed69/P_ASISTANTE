#!/usr/bin/env bash
# scripts/entrypoint.sh — Corre DENTRO del contenedor antes de arrancar OpenClaw
# OpenClaw maneja su propia base de datos internamente; este entrypoint solo
# asegura que el directorio de datos tenga los permisos correctos y arranca el gateway.
set -euo pipefail

echo "[entrypoint] Iniciando OpenClaw gateway..."
exec node dist/index.js gateway --bind lan --port 18789 --allow-unconfigured
