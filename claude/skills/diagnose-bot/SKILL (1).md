---
name: diagnose-bot
description: Procedimiento sistemático para diagnosticar por qué un bot no responde, está unhealthy, o tiene comportamiento extraño. Usar cuando el monitor.py alertó por OOM, healthcheck fallido, o degradación de OpenRouter. También para cuando un cliente reporta que el bot no contesta.
---

# Diagnosticar bot con problemas

## Síntomas que disparan este skill
- `docker compose ps` muestra bot como `unhealthy` o `restarting`
- Telegram alert de OOM, healthcheck failure, o degradación de API
- Cliente reporta que el bot no responde o responde "Error de API"
- `actions_log` tiene errores recientes

## Procedimiento — orden estricto, no saltar pasos

### Paso 1 — Estado del contenedor
```bash
docker compose ps <bot>
docker stats <bot> --no-stream    # uso de RAM y CPU actual
```

Interpretación:
- `Up X seconds (healthy)` → contenedor OK, problema en otra capa
- `Up X seconds (unhealthy)` → healthcheck falla, ir a Paso 2
- `Restarting` → loop de reinicio, ir a Paso 3
- `Exited (137)` → OOM kill, ir a Paso 4

### Paso 2 — Healthcheck falla
```bash
docker exec <bot> curl -fsS http://127.0.0.1:18789/healthz
```

Si responde 200 → falso positivo del healthcheck (raro). Revisar `interval`/`timeout`.
Si responde error → ir a Paso 5 (logs).

### Paso 3 — Loop de reinicio
```bash
docker compose logs --tail=200 <bot>
```

Buscar en los logs:
- `EACCES` / `permission denied` → problema de mount o permisos de volumen
- `Cannot connect to OpenRouter` → ir a Paso 6 (red)
- `SQLite database is locked` → busy_timeout no se aplicó, revisar entrypoint.sh
- `Out of memory` → ir a Paso 4

### Paso 4 — OOM
```bash
# Cuántos OOMs en última hora
sqlite3 data/fleet.db "PRAGMA key='$DB_ENCRYPTION_KEY';
  SELECT COUNT(*) FROM actions_log
  WHERE bot_id='<bot>' AND action_type='system.oom'
  AND timestamp > datetime('now', '-1 hour');"
```

- 1 OOM en última hora → puede ser una operación puntual (PDF grande). Esperar.
- 2+ OOM en última hora → escalar:
  ```bash
  ./scripts/scale-bot.sh <bot> 768m
  ```
- Si ya está en 768m y sigue OOM → revisar si hay un bug que causa memory leak.
  Ver últimas líneas del log antes del OOM para ver qué estaba procesando.

### Paso 5 — Logs del bot
```bash
docker compose logs --tail=500 <bot> | grep -iE "error|fatal|exception|killed"
```

Patterns comunes:
- `ECONNREFUSED openrouter.ai` → problema DNS o red, ir a Paso 6
- `401 Unauthorized` → token de OpenRouter expirado o revocado, revisar `.env`
- `429 Too Many Requests` → rate limit, dreamer.py debería estar manejando esto
- `EACCES /home/node/.openclaw/...` → mount de volumen mal o permisos
- `Cannot find module` → la imagen Docker está corrupta, hacer `docker compose pull`

### Paso 6 — Red y DNS
```bash
docker exec <bot> curl -v https://openrouter.ai/api/v1/models 2>&1 | head -20
docker exec <bot> nslookup openrouter.ai
```

Si DNS falla → revisar `dns:` en docker-compose.yml (debe tener `1.1.1.1` y `8.8.8.8`).
Si curl falla con SSL → reloj del contenedor desincronizado, hacer `docker compose restart <bot>`.

### Paso 7 — Estado de fleet.db
```bash
sqlite3 data/fleet.db "PRAGMA key='$DB_ENCRYPTION_KEY';
  SELECT id, status, last_active FROM bots WHERE id='<bot>';
  SELECT timestamp, action_type, status FROM actions_log
  WHERE bot_id='<bot>' ORDER BY timestamp DESC LIMIT 10;
  SELECT timestamp, model, retry_count, fallback_model, resolved
  FROM rate_limit_events WHERE bot_id='<bot>'
  ORDER BY timestamp DESC LIMIT 5;"
```

Interpretación:
- `bots.status='error'` → monitor.py marcó algo. Ver `actions_log` reciente.
- Muchos `rate_limit_events` con `resolved=0` → OpenRouter degradado. Verificar
  status.openrouter.ai y considerar cambiar `model_default` temporalmente.

### Paso 8 — Si nada de lo anterior aplica
```bash
docker compose restart <bot>
sleep 90    # esperar start_period completo
docker compose ps <bot>
```

Si después del restart sigue mal, hacer recreate completo:
```bash
docker compose stop <bot>
docker compose rm -f <bot>
docker compose up -d <bot>
```

Si sigue mal después de recreate, restaurar desde backup de la semana anterior:
```bash
# Ver backups disponibles
ls -lh /mnt/user-data/backups/
# Descifrar el backup
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
  -in backup-<bot>-<fecha>.tar.gz.enc \
  -out backup-<bot>-<fecha>.tar.gz \
  -pass env:DB_ENCRYPTION_KEY
tar -xzf backup-<bot>-<fecha>.tar.gz
# Confirmar con Luciel antes de sobreescribir bots/<bot>/
```

## Lo que NUNCA hacer durante diagnóstico

- **NO** hacer `docker compose down` — eso afecta a TODOS los bots
- **NO** borrar `bots/<bot>/data/` — ahí está la memoria del bot, irreemplazable
  (excepto si vas a restaurar backup)
- **NO** modificar `.env` en producción sin avisar a Luciel — los tokens son críticos
- **NO** asumir que el cliente está mintiendo. Si dice que el bot no responde,
  empezá por Paso 1 antes de cuestionar el reporte.

## Reportar al admin

Después de diagnosticar, escribí en `STATUS.md`:
```
## Incidente <fecha>
- Bot afectado: <bot>
- Síntoma: <qué reportó el cliente o el monitor>
- Causa raíz: <Paso N reveló X>
- Fix aplicado: <comando ejecutado>
- Tiempo de downtime: <duración>
- Acción de seguimiento: <si requiere algo más, ej: aumentar plan del cliente>
```
