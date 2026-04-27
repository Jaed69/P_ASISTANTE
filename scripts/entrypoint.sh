#!/usr/bin/env bash
# scripts/entrypoint.sh — Corre DENTRO del contenedor antes de arrancar OpenClaw
# Orden: checkpoint WAL → activar WAL → integrity check → restore si falla → arrancar
set -euo pipefail

DB_PATH="/home/node/.openclaw/data/openclaw.sqlite"
BACKUP_DIR="/home/node/.openclaw/data/backups"

# ── PASO 1: Checkpoint WAL antes del integrity check ─────────────────────────
if [ -f "$DB_PATH" ]; then
  echo "[entrypoint] Forzando WAL checkpoint..."
  sqlite3 "$DB_PATH" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true

  # ── PASO 2: Activar WAL mode (idempotente) ─────────────────────────────────
  echo "[entrypoint] Activando WAL mode + busy_timeout..."
  sqlite3 "$DB_PATH" "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA busy_timeout=5000;" 2>/dev/null || true

  # ── PASO 3: Integrity check ────────────────────────────────────────────────
  echo "[entrypoint] Ejecutando PRAGMA integrity_check..."
  RESULT=$(sqlite3 "$DB_PATH" "PRAGMA integrity_check;" 2>/dev/null || echo "error")

  if [ "$RESULT" != "ok" ]; then
    echo "[entrypoint] ⚠️ SQLite integrity check failed: $RESULT"

    # Buscar backup más reciente
    LATEST=$(ls -t "$BACKUP_DIR"/*.sqlite 2>/dev/null | head -1 || true)

    if [ -n "$LATEST" ]; then
      echo "[entrypoint] Restaurando desde backup: $LATEST"
      cp "$LATEST" "$DB_PATH"
      echo "[entrypoint] ✓ Restaurado desde $LATEST"
    else
      echo "[entrypoint] Sin backup disponible — eliminando DB corrupta y arrancando limpio"
      rm -f "$DB_PATH" "$DB_PATH-wal" "$DB_PATH-shm"
    fi
  else
    echo "[entrypoint] ✓ Integrity check OK"
  fi
else
  echo "[entrypoint] No existe DB aún (primer arranque) — OpenClaw la creará"
fi

# ── PASO 4: Arrancar OpenClaw ────────────────────────────────────────────────
echo "[entrypoint] Iniciando OpenClaw..."
exec openclaw start
