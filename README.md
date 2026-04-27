# OpenClaw Fleet

SaaS de asistentes IA personales basado en [OpenClaw](https://github.com/openclaw), desplegado en Oracle Cloud ARM con Docker + gVisor + OpenRouter.

> **Producto comercial:** $400-600 setup + $150-200/mes por cliente.

---

## Requisitos previos

### En el VPS (producción)

- **OS:** Ubuntu 24.04 Minimal ARM (aarch64)
- **Docker Engine** + Docker Compose plugin
- **gVisor** (`runsc`) — o fallback automático con `cap_drop`
- **Python 3.12** + `sqlcipher3`
- **Tailscale** (acceso admin) + **Cloudflare Tunnel** (webhooks WhatsApp)

> Para instalar todo de una vez en un VPS virgen, usá el script `scripts/vps-setup.sh` (Fase 1).

### En desarrollo local

- Docker Engine + Docker Compose
- Bash (Linux/macOS/WSL2)
- Python 3.12 (solo para `scripts/db_init.py` y `scripts/db_helper.py`)

---

## Pasos para levantar el proyecto

### 1. Clonar el repositorio

```bash
git clone https://github.com/Jaed69/P_ASISTANTE.git
cd P_ASISTANTE
```

### 2. Copiar y configurar `.env`

```bash
cp .env.example .env
nano .env
```

**Valores obligatorios a completar:**

| Variable | Descripción |
|----------|-------------|
| `OPENROUTER_API_KEY` | Tu clave de API de [OpenRouter](https://openrouter.ai/keys) |
| `DB_ENCRYPTION_KEY` | Clave de cifrado para `fleet.db`. Generala con: `openssl rand -hex 32` |
| `BOTS` | Lista de bots separados por espacios, ej: `"personal researcher"` |
| `<nombre>_TELEGRAM_TOKEN` | Token de @BotFather para cada bot (opcional para Telegram) |
| `<nombre>_MODEL` | Modelo de OpenRouter para cada bot (por defecto: `nvidia/llama-3.3-nemotron-super-49b-v1`) |

**Ejemplo mínimo de `.env`:**

```bash
OPENROUTER_API_KEY=sk-or-v1-tu-clave-aqui
DB_ENCRYPTION_KEY=generado-con-openssl-rand-hex-32
BOTS="personal"

personal_TELEGRAM_TOKEN=
personal_MODEL=nvidia/llama-3.3-nemotron-super-49b-v1
personal_TOKEN=
```

> **Nota:** Los tokens `<nombre>_TOKEN` se generan automáticamente con `./setup.sh`. No los rellenas a mano.

### 3. Ejecutar `./setup.sh`

Este script hace todo:

- Valida que `.env` esté completo
- Detecta el runtime seguro (`runsc` o fallback `runc` + `cap_drop`)
- Crea `data/fleet.db` (SQLCipher) si no existe
- Genera tokens seguros para cada bot
- Crea directorios y archivos de configuración por bot
- Genera `nginx.conf` y `docker-compose.yml`

```bash
./setup.sh
```

### 4. Levantar los servicios

```bash
docker compose up -d
```

Esto arranca:
- Todos los bots configurados en `BOTS`
- Nginx en `127.0.0.1:18788`

### 5. Verificar estado

```bash
docker compose ps
docker compose logs -f <nombre-del-bot>
```

### 6. Acceder a la UI de cada bot

Desde el VPS (vía Tailscale o SSH tunnel):

```
http://127.0.0.1:18788/<nombre-del-bot>/
```

Ejemplo:
```
http://127.0.0.1:18788/personal/
```

---

## Agregar un nuevo bot

```bash
./add-bot.sh <nombre> [telegram_token] [modelo]
```

Ejemplos:
```bash
./add-bot.sh coder
./add-bot.sh coder "123456:ABCdef..." "anthropic/claude-haiku-4-5"
```

Luego:
```bash
./setup.sh           # regenera docker-compose.yml con el nuevo bot
docker compose up -d # levanta todo
```

---

## Comandos útiles

| Comando | Descripción |
|---------|-------------|
| `./setup.sh` | Regenera tokens, configs, `docker-compose.yml`, `nginx.conf` |
| `./scripts/test-gvisor.sh` | Detecta si gVisor funciona y aplica fallback seguro |
| `./scripts/audit.sh` | 7 checks de seguridad del fleet |
| `./scripts/audit.sh --fix` | Corrige automáticamente lo que puede |
| `./scripts/rotate-token.sh <bot>` | Rota token de un bot sin pérdida de memoria |
| `./scripts/scale-bot.sh <bot> <ram>` | Ajusta RAM de un bot manualmente (respuesta a OOM) |
| `docker compose up -d` | Levanta todo el fleet |
| `docker compose ps` | Estado y healthchecks de todos los servicios |
| `docker compose logs -f <bot>` | Logs en tiempo real de un bot |
| `docker compose restart <bot>` | Reinicia un bot tras editar `SOUL.md` |

---

## Estructura del proyecto

```
P_ASISTANTE/
├── bots/
│   └── <nombre>/              # Un directorio por bot
│       ├── config/
│       │   ├── openclaw.json   # Config de OpenClaw (modelo, gateway)
│       │   ├── SOUL.md         # Personalidad del bot
│       │   └── agents/
│       │       └── main/
│       │           └── agent/
│       │               └── models.json
│       ├── workspace/          # Archivos de trabajo del bot
│       ├── data/               # SQLite interno del bot + backups
│       └── skills/             # Skills instaladas
├── scripts/
│   ├── test-gvisor.sh          # Detecta gVisor ARM + fallback seguro
│   ├── entrypoint.sh           # Corre dentro de cada contenedor (WAL + integrity check)
│   ├── db_init.py              # Crea fleet.db con SQLCipher
│   ├── db_helper.py            # Helper obligatorio para conexiones a fleet.db
│   ├── audit.sh                # Checks de seguridad (Fase 1)
│   ├── dreamer.py              # Consolidación de memoria (Fase 1)
│   ├── monitor.py              # Monitoreo y alertas (Fase 1)
│   ├── backup.py               # Backups VACUUM INTO (Fase 1)
│   ├── rotate-token.sh         # Rotación de tokens (Fase 1)
│   └── scale-bot.sh            # Escalado manual de RAM (Fase 1)
├── templates/
│   ├── SOUL.md                 # Template de personalidad
│   ├── models.json             # Template de modelos
│   └── skills/
│       └── approved-skills.txt # Lista de skills permitidas
├── data/
│   └── fleet.db                # Base central (clientes, bots, tokens, uso API)
├── claude/skills/              # Documentación operativa para Claude Code
├── setup.sh                    # Script principal de inicialización
├── add-bot.sh                  # Agrega un nuevo bot al fleet
├── docker-compose.yml          # Generado por setup.sh — NO editar manualmente
├── nginx.conf                  # Generado por setup.sh — NO editar manualmente
├── runtime.env                 # Generado por test-gvisor.sh — NO editar manualmente
├── .env                        # Configuración y secretos — NUNCA subir a git
├── .env.example                # Plantilla de .env
└── README.md                   # Este archivo
```

---

## Notas de seguridad

- **`.env` y `runtime.env`** contienen secretos. Nunca los subas a git.
- **`data/fleet.db`** está cifrada con SQLCipher. La clave es `DB_ENCRYPTION_KEY`.
- **Tokens Google OAuth** se almacenan cifrados en `fleet.db`, nunca en texto plano.
- **Backups:** Solo usar `VACUUM INTO`. Está prohibido `cp`, `tar`, o copiar archivos `.db` directamente.
- **Puertos:** Solo Nginx expone un puerto al host (`127.0.0.1:18788:80`). Ningún bot expone puerto directamente.
- **Acceso externo:** Solo via Tailscale (admin) y Cloudflare Tunnel (webhooks WhatsApp/Twilio).

---

## Arquitectura

```
┌─────────────────────────────────────────┐
│           Cloudflare Tunnel             │
│         (webhooks WhatsApp)             │
└─────────────┬───────────────────────────┘
              │
┌─────────────▼───────────────────────────┐
│              Nginx :18788               │
│         (único puerto al host)          │
└──────┬────────────┬─────────────────────┘
       │            │
   ┌───▼───┐    ┌───▼───┐    ┌───▼───┐
   │ bot 1 │    │ bot 2 │    │ bot N │
   │gVisor │    │gVisor │    │gVisor │
   └───────┘    └───────┘    └───────┘
       │            │            │
       └────────────┴────────────┘
                    │
            ┌───────▼───────┐
            │   OpenRouter   │
            │  (API LLMs)    │
            └───────────────┘
```

---

## Soporte

Para diagnóstico y troubleshooting, usá el skill `claude/skills/diagnose-bot/`.

Para agregar bots nuevos con Claude Code, usá el skill `claude/skills/add-new-bot/`.

---

> **Estado:** Fase 0 completada. Fase 1 en progreso.
> Ver `STATUS.md` para el estado detallado del proyecto.
