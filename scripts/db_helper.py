#!/usr/bin/env python3
# scripts/db_helper.py — Helper obligatorio para TODA conexión a fleet.db
# Uso: from scripts.db_helper import open_fleet_db
# NUNCA conectar directamente con sqlcipher3.connect.

import os
import sys

try:
    import sqlcipher3
except ImportError:
    print("Error: sqlcipher3 no instalado. Ejecuta: pip install sqlcipher3", file=sys.stderr)
    sys.exit(1)


def open_fleet_db(path="data/fleet.db"):
    """
    Abre fleet.db con todos los PRAGMAs en orden correcto.

    Orden CRÍTICO:
      1. PRAGMA key  — debe ser la primera sentencia
      2. PRAGMA busy_timeout=5000 — después de key, antes de cualquier operación

    Lanza RuntimeError si DB_ENCRYPTION_KEY no está en el entorno.
    """
    key = os.environ.get("DB_ENCRYPTION_KEY")
    if not key:
        raise RuntimeError("DB_ENCRYPTION_KEY no está definida en el entorno")

    conn = sqlcipher3.connect(path)

    # 1. PRIMERO la clave
    conn.execute(f"PRAGMA key='{key}';")

    # 2. busy_timeout — tolerancia ante locks (siempre después de key)
    conn.execute("PRAGMA busy_timeout=5000;")

    return conn
