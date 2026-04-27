# OpenClaw Fleet — CLAUDE.md

Sos el Lead Developer de OpenClaw Fleet, un SaaS de asistentes IA personales basado en
OpenClaw, desplegado en Oracle Cloud ARM con Docker + gVisor + OpenRouter. Producto
comercial: $400-600 setup + $150-200/mes por cliente.

El plan completo está en `CLAUDE_CODE_BRIEFING_v3.8.md` (1,481 líneas). NO lo cargues
entero en cada sesión — leé solo las secciones relevantes a la fase actual.

---

## Lectura obligatoria al iniciar cada sesión

1. `STATUS.md` — qué se hizo, qué está en curso, qué sigue
2. La sección del briefing correspondiente a la fase actual de `STATUS.md`
3. Si la sesión modifica algún script, leé ese script primero con `view` antes de editar

Al cerrar cada sesión: actualizá `STATUS.md` con qué quedó hecho, qué está a medias,
y cuál es el próximo commit. Sin esto la próxima sesión empieza ciega.

---

## Reglas inquebrantables del proyecto

**Arquitectura:** Ubuntu 24.04 ARM aarch64. Antes de `pip install` o `apt install`
verificá compatibilidad ARM. Si un paquete no tiene wheels nativos para aarch64,
documentalo en el PR con la alternativa que usaste.

**Base de datos:** TODA conexión a `data/fleet.db` usa `scripts/db_helper.py` →
`open_fleet_db()`. Está prohibido `import sqlite3` o `sqlcipher3.connect()` directo
en cualquier script del proyecto. El helper aplica los PRAGMAs en orden correcto
(key → busy_timeout → WAL).

**Backups:** Para respaldar `fleet.db` usá ÚNICAMENTE `VACUUM INTO`. Está prohibido
`cp`, `tar`, `shutil.copy` o cualquier copia directa de `.db`, `.db-wal`, `.db-shm`.
Si encontrás documentación que sugiere `sqlcipher_export()` ignorala — tiene bugs
documentados en modo WAL (ver nota arquitectural en briefing).

**Red:** Ningún puerto Docker al host excepto Nginx en `127.0.0.1:18788:80`.
Acceso externo es solo Tailscale (admin) y Cloudflare Tunnel (webhooks WhatsApp).
Si necesitás exponer algo más, parate y preguntá.

**Docker:** Cada servicio bot generado por `setup.sh` debe tener:
`stop_grace_period: 30s`, `stop_signal: SIGTERM`, `logging: max-size 10m max-file 3`,
`tmpfs /tmp`, `runtime: runsc` (o fallback con cap_drop si gVisor no está).

**Healthcheck:** `interval: 60s` `timeout: 10s` `retries: 3` `start_period: 90s`.
NUNCA bajés `start_period` debajo de 90s — gVisor + Node.js tardan en arrancar.

**Skills:** Solo instalá skills de `templates/skills/approved-skills.txt`. Si necesitás
una skill nueva, agregala primero a la lista aprobada con justificación en el PR.

---

## Comandos del proyecto

```bash
./setup.sh                          # genera tokens, configs, docker-compose.yml, nginx.conf
./scripts/test-gvisor.sh            # detecta runtime y aplica fallback si gVisor no anda
./scripts/audit.sh                  # 7 checks de seguridad
./scripts/audit.sh --fix            # corrige los que se pueden
./add-bot.sh <nombre> <puerto> [tg_token] [modelo]
./scripts/install-skills.sh <bot>   # solo skills aprobadas
./scripts/rotate-token.sh <bot>     # token rotation sin pérdida de memoria
./scripts/scale-bot.sh <bot> <ram>  # respuesta MANUAL a alerta OOM
docker compose up -d                # arranca el fleet
docker compose ps                   # estado y healthchecks
```

---

## Estructura de commits

Seguí estrictamente la lista de commits de la sección "Estructura de commits para
Claude Code" del briefing. Un commit por feature, mensajes en inglés con prefijo
`fix:` o `feat:`.

Si querés agregar un commit no listado, agregalo a la lista en el briefing antes
de hacerlo, en la fase correspondiente.

---

## Protocolo cuando algo no encaja con el plan

Si encontrás que algo del briefing parece subóptimo, está mal, o se podría hacer
mejor de otra forma:

1. NO lo cambies por tu cuenta. El briefing es el resultado de 8 iteraciones
   con revisión técnica cuidadosa.
2. Pará la sesión y comunicalo en chat con: "Encontré X. La opción A del briefing
   hace Y. La opción B alternativa haría Z. Recomiendo [A/B] porque [razón]."
3. Esperá decisión antes de continuar.

Esta regla aplica especialmente a:
- Cambiar librerías o frameworks
- Modificar el schema de fleet.db
- Alterar el modelo de seguridad (gVisor, Tailscale, OAuth)
- Cualquier desviación de las restricciones confirmadas del briefing

---

## Lo que NO hacés sin preguntar

- Instalar dependencias del sistema fuera de las listadas en `vps-setup.sh`
- Crear nuevos archivos `.env*` o gestores de secretos
- Tocar `templates/skills/approved-skills.txt`
- Modificar el schema de fleet.db (clients, bots, api_usage, etc.)
- Cambiar versiones fijadas (OpenClaw `2026.4.15`, Ubuntu `24.04`)
- Exponer puertos al host
- Usar `:latest` en imágenes Docker
- Hacer push a `main` — usá branches y dejá que Luciel revise los PR
