#!/usr/bin/env python3
# scripts/db_init.py — Crea data/fleet.db con SQLCipher y schema completo
# Uso: python3 scripts/db_init.py
# Si fleet.db ya existe, no hace nada (idempotente).

import os
import sys

# ── Validar dependencia ──────────────────────────────────────────────────────
try:
    import sqlcipher3
except ImportError:
    print("Error: sqlcipher3 no instalado. Ejecuta: pip install sqlcipher3", file=sys.stderr)
    sys.exit(1)

# ── Configuración ────────────────────────────────────────────────────────────
DB_PATH = os.environ.get("FLEET_DB_PATH", "data/fleet.db")
KEY = os.environ.get("DB_ENCRYPTION_KEY")

if not KEY:
    print("Error: DB_ENCRYPTION_KEY no está definida en el entorno", file=sys.stderr)
    sys.exit(1)

# ── Si ya existe, no tocar ───────────────────────────────────────────────────
if os.path.exists(DB_PATH):
    print(f"✓ {DB_PATH} ya existe — no se modifica.")
    sys.exit(0)

# ── Crear directorio si no existe ────────────────────────────────────────────
os.makedirs(os.path.dirname(DB_PATH) or ".", exist_ok=True)

# ── Conectar y aplicar PRAGMAs en orden CRÍTICO ──────────────────────────────
conn = sqlcipher3.connect(DB_PATH)

# 1. PRIMERO la clave (sin esto no se pueden ejecutar otros PRAGMAs)
conn.execute(f"PRAGMA key='{KEY}';")

# 2. busy_timeout — tolerancia ante locks
conn.execute("PRAGMA busy_timeout=5000;")

# 3. WAL mode — lecturas no bloquean escrituras
conn.execute("PRAGMA journal_mode=WAL;")

# 4. Synchronous balance seguridad/velocidad
conn.execute("PRAGMA synchronous=NORMAL;")

# 5. Auto-checkpoint cada 1000 páginas
conn.execute("PRAGMA wal_autocheckpoint=1000;")

# ── Crear tablas ─────────────────────────────────────────────────────────────
conn.executescript("""
CREATE TABLE clients (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  email       TEXT UNIQUE,
  phone       TEXT,
  plan        TEXT DEFAULT 'basic',
  status      TEXT DEFAULT 'trial',
  setup_fee   REAL,
  monthly_fee REAL,
  created_at  TEXT DEFAULT (datetime('now')),
  notes       TEXT
);

CREATE TABLE bots (
  id              TEXT PRIMARY KEY,
  client_id       TEXT REFERENCES clients(id),
  bot_name        TEXT NOT NULL,
  channel         TEXT,
  telegram_token  TEXT,
  whatsapp_number TEXT,
  model_default   TEXT DEFAULT 'deepseek/deepseek-v4-flash',
  gateway_token   TEXT NOT NULL,
  volume_path     TEXT NOT NULL,
  status          TEXT DEFAULT 'running',
  created_at      TEXT DEFAULT (datetime('now')),
  last_active     TEXT
);

CREATE TABLE api_usage (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  bot_id      TEXT REFERENCES bots(id),
  date        TEXT NOT NULL,
  tokens_in   INTEGER DEFAULT 0,
  tokens_out  INTEGER DEFAULT 0,
  cost_usd    REAL DEFAULT 0,
  model       TEXT
);

CREATE TABLE gateway_tokens (
  bot_id      TEXT REFERENCES bots(id),
  token_hash  TEXT NOT NULL,
  created_at  TEXT DEFAULT (datetime('now')),
  revoked_at  TEXT,
  PRIMARY KEY (bot_id, token_hash)
);

CREATE TABLE google_tokens (
  client_id       TEXT PRIMARY KEY REFERENCES clients(id),
  access_token    TEXT,
  refresh_token   TEXT,
  token_expiry    TEXT,
  scopes          TEXT,
  updated_at      TEXT DEFAULT (datetime('now'))
);

CREATE TABLE actions_log (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  bot_id      TEXT REFERENCES bots(id),
  timestamp   TEXT DEFAULT (datetime('now')),
  action_type TEXT NOT NULL,
  status      TEXT NOT NULL,
  details     TEXT,
  approved_by TEXT
);

CREATE TABLE rate_limit_events (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  bot_id         TEXT REFERENCES bots(id),
  timestamp      TEXT DEFAULT (datetime('now')),
  model          TEXT,
  retry_count    INTEGER,
  fallback_model TEXT,
  resolved       INTEGER DEFAULT 0
);
""")

conn.commit()
conn.close()

print(f"✓ {DB_PATH} creado con SQLCipher + WAL + schema completo.")
