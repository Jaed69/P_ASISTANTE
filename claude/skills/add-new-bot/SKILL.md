---
name: add-new-bot
description: Procedimiento completo para agregar un bot nuevo al fleet, incluyendo registro en fleet.db, generación de tokens, y configuración inicial. Usar cuando se necesite onboardear un cliente nuevo o crear un bot adicional.
---

# Agregar bot nuevo al fleet

## Cuándo usar
- Onboarding de cliente nuevo
- Crear bot adicional para cliente existente (ej: `personal` + `clientes`)
- Pruebas en desarrollo

## Procedimiento

### 1. Validar parámetros
- Nombre del bot: solo letras, números y guión bajo (`^[a-zA-Z0-9_]+$`)
- No debe existir ya en `BOTS=` del `.env`
- Modelo válido en `templates/config/models.json`

### 2. Registrar en fleet.db PRIMERO
Antes de tocar `.env` o crear directorios, insertá en la DB:

```python
from scripts.db_helper import open_fleet_db
import uuid, secrets, hashlib

bot_id = nombre_validado
client_id = str(uuid.uuid4())
gateway_token = secrets.token_hex(32)
token_hash = hashlib.sha256(gateway_token.encode()).hexdigest()

conn = open_fleet_db()
# Cliente nuevo (si no existe)
conn.execute("INSERT INTO clients (id, name, plan, status) VALUES (?, ?, 'basic', 'trial')",
             (client_id, nombre_cliente))
# Bot
conn.execute("""INSERT INTO bots (id, client_id, bot_name, channel,
                model_default, gateway_token, volume_path)
                VALUES (?, ?, ?, ?, ?, ?, ?)""",
             (bot_id, client_id, bot_name, channel, modelo, token_hash,
              f"./bots/{bot_id}/"))
# Token rotativo
conn.execute("INSERT INTO gateway_tokens (bot_id, token_hash) VALUES (?, ?)",
             (bot_id, token_hash))
conn.commit()
```

### 3. Llamar a add-bot.sh
```bash
./add-bot.sh <nombre> <puerto> "<telegram_token>" "<modelo>"
```
Esto agrega las variables al `.env`.

### 4. Ejecutar setup.sh
```bash
./setup.sh
```
Genera el directorio `bots/<nombre>/`, los archivos de identidad, y actualiza
`docker-compose.yml`.

### 5. Personalizar SOUL.md y USER.md
Si es onboarding real (no test), generá los archivos via API de Claude usando
el formulario de onboarding. Si es test, dejá los templates por defecto.

### 6. Levantar el contenedor
```bash
docker compose up -d <nombre>
```

### 7. Verificar
- `docker compose ps` muestra el bot como `running` y eventualmente `healthy`
- `./scripts/audit.sh` no reporta nuevos issues
- Logs limpios en los primeros 90s: `docker compose logs -f <nombre>`

### 8. Si tiene Google: ejecutar OAuth
```bash
./scripts/google-auth.sh <nombre>
```
(Solo en Fase 2+. En Fase 4, esto lo hace el panel de onboarding.)

### 9. Registrar en STATUS.md
Agregá una línea: "Bot `<nombre>` agregado para cliente `<nombre_cliente>`,
plan `<plan>`, fecha `YYYY-MM-DD`."

## Errores comunes a evitar

- **NO** registrar el bot en `fleet.db` después de levantar el contenedor.
  El monitor.py lo ve como "bot huérfano" y puede generar alertas falsas.
- **NO** olvidar el INSERT en `gateway_tokens` — sin eso, `rotate-token.sh`
  no funciona porque busca el token actual ahí.
- **NO** poner el token plano en `bots.gateway_token` — siempre el hash SHA256.
- **NO** asumir que el cliente quiere los modelos por defecto. Preguntá si
  el caso de uso justifica modelos más caros (Claude Sonnet) o si queda con DeepSeek.

## Rollback si algo falla

Si el bot no arranca correctamente:
```bash
docker compose stop <nombre>
docker compose rm -f <nombre>
rm -rf bots/<nombre>/
# En fleet.db:
conn.execute("DELETE FROM bots WHERE id=?", (bot_id,))
conn.execute("DELETE FROM gateway_tokens WHERE bot_id=?", (bot_id,))
# En .env: borrar las variables del bot manualmente
./setup.sh   # regenera compose sin el bot
```
