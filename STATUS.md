# OpenClaw Fleet — STATUS

> Este archivo lo actualiza Claude Code al final de CADA sesión.
> Sin esto, la próxima sesión empieza ciega.

---

## Fase actual

**Fase 0 — Correcciones y bugs base** (completada)

## Última sesión

2026-04-27 — Fix: imagen OpenClaw actualizada a `2026.4.26-slim` + comando entrypoint corregido

## En curso

- [x] Bug 1 — Nginx subpath routing and single host port exposure
- [x] Bug 4 — stop_grace_period: 30s + stop_signal: SIGTERM en cada bot
- [x] Bug 3 — Volume mounts separados: config, workspace, data, skills
- [x] Healthcheck calibrado: interval 60s / timeout 10s / retries 3 / start_period 90s
- [x] Token interpolation fix: valor escrito directamente en docker-compose.yml
- [x] Logging rotation (max-size 10m, max-file 3) y tmpfs /tmp en cada bot
- [x] Imagen fijada a `ghcr.io/openclaw/openclaw:2026.4.26-slim` (no :latest)
- [x] `scripts/test-gvisor.sh` — detección gVisor ARM + fallback cap_drop/AppArmor
- [x] `scripts/entrypoint.sh` — corre DENTRO del contenedor (comando: `node dist/index.js gateway --bind lan --port 18789 --allow-unconfigured`)
- [x] `scripts/db_init.py` — crea `data/fleet.db` con SQLCipher + schema completo
- [x] `scripts/db_helper.py` — helper obligatorio `open_fleet_db()`
- [x] **Integración en `setup.sh`**:
  - Valida `DB_ENCRYPTION_KEY` en `.env`
  - Ejecuta `test-gvisor.sh` y lee `runtime.env` para inyectar runtime/security
  - Ejecuta `db_init.py` si `data/fleet.db` no existe
  - Cada bot en `docker-compose.yml` incluye `entrypoint: ["/entrypoint.sh"]` + volumen `scripts/entrypoint.sh`
  - Inyecta `runtime: runsc` o `security_opt`/`cap_drop`/`cap_add` según resultado de test-gvisor
- [x] `.env.example` actualizado con `DB_ENCRYPTION_KEY` e imagen `2026.4.26-slim`
- [x] `README.md` con paso a paso para levantar el proyecto
- [x] `CLAUDE.md` con reglas de git workflow

## Commits realizados

- `e230551` — `fix: nginx subpath routing and single host port exposure`
- `ce7aaf6` — `feat: gvisor arm detection with v8 jit test and cap_drop fallback`
- `49483f2` — `feat: add entrypoint.sh with wal checkpoint before integrity check and auto-restore`
- `74b17f9` — `feat: add sqlcipher fleet.db schema with wal mode and all tables`
- `a665b86` — `feat: add db_helper.py centralized connection opener for all scripts`
- `3c4d793` — `docs: add git workflow rule to push after every validated step`
- `b59b930` — `docs: clarify git workflow with branch rules and real-time validation exception`
- `93ca8eb` — `feat: integrate test-gvisor, entrypoint, and db_init into setup.sh`
- `6ff0d00` — `docs: update STATUS.md marking Phase 0 complete`
- `d1b1a56` — `docs: add README.md with step-by-step setup instructions`
- `52f78d1` — `fix: update OpenClaw image to 2026.4.26-slim and correct entrypoint command`

## Próximo commit

Fase 0 completada. Próximo paso: **Fase 1 — Infraestructura base**

1. `feat: add vps-setup.sh for Ubuntu 24.04 ARM`
2. `feat: add dreamer.py incremental daily and weekly pruning with retry fallback`
3. `feat: add monitor.py with healthcheck polling, oomkilled listener, and degradation alerts`
4. `feat: add backup.py with vacuum-into snapshot, openssl encryption, wal_checkpoint and post-backup vacuum`
5. `feat: add rotate-token.sh with graceful restart and fleet.db update`
6. `feat: add scale-bot.sh for manual ram scaling triggered by oom alerts`

## Bloqueado por

- [ ] Ejecutar `scripts/test-gvisor.sh` en entorno con Docker para validar Tests 2-4 en ARM
      → actualmente solo se validó sintaxis bash; se requiere Docker + imagen OpenClaw en VPS
- [ ] Confirmar si OpenClaw `/healthz` requiere Authorization header
      → docker run y test directo en VPS

## Decisiones tomadas en sesión

- El repositorio no tenía `.env.example` al inicio de la sesión anterior, pero apareció
  después de la primera interacción. Se actualizó para reflejar la nueva
  arquitectura sin puertos por bot.
- Se unificaron los fixes del compose en un solo commit porque `setup.sh`
  genera todo de una pieza.
- **Opción B elegida:** crear scripts primero, integrar en `setup.sh`/`docker-compose.yml` en paso posterior.
- `scripts/test-gvisor.sh` escribe `runtime.env` (no modifica `.env`) para no contaminar secretos.
- `scripts/db_init.py` es idempotente: si `data/fleet.db` existe, sale limpiamente sin tocar nada.
- `scripts/db_helper.py` tiene exactamente una función pública (`open_fleet_db`), sin helpers extra.
- `setup.sh` maneja graceful degradation: si `python3` no está disponible, advierte pero no falla
  (permite setup en entornos de desarrollo sin Python instalado).
- `setup.sh` también maneja ausencia de `scripts/test-gvisor.sh` (warning, no error).
- **Imagen OpenClaw actualizada de `2026.4.15` → `2026.4.26-slim`** (última versión disponible, con soporte ARM64).
- **Entrypoint corregido:** `openclaw start` no existe en la imagen. El comando correcto es
  `node dist/index.js gateway --bind lan --port 18789 --allow-unconfigured`.
- **`sqlite3` no está en la imagen `node:24-bookworm-slim`**, por lo que `entrypoint.sh`
  ya no intenta hacer WAL checkpoint ni integrity check. OpenClaw maneja su propia DB internamente.

## Notas para Luciel

- **Fase 0 COMPLETADA** ✅
- Todos los scripts están integrados en `setup.sh` y generan `docker-compose.yml` completo.
- El siguiente paso es **Fase 1 — Infraestructura base**:
  - `vps-setup.sh` (instalador Ubuntu 24.04 ARM)
  - `dreamer.py` (consolidación de memoria + pruning)
  - `monitor.py` (monitoreo y alertas)
  - `backup.py` (VACUUM INTO + cifrado OpenSSL)
  - `rotate-token.sh` y `scale-bot.sh`
- Las skills en `claude/skills/` (add-new-bot, diagnose-bot) son documentación
  operativa para Fases 2-4; no requieren implementación en Fase 0.
- Python3 no está disponible en el entorno de desarrollo actual; los scripts Python
  fueron escritos según el briefing pero no se pudo hacer `py_compile`. Validar en VPS.
- **Instrucciones para actualizar la VM** (ver sección "Cómo actualizar la VM" abajo).

---

## Cómo actualizar la VM

Si ya tenés el repo clonado en la VM (`~/P_ASISTANTE`), ejecutá estos pasos:

```bash
cd ~/P_ASISTANTE

# 1. Guardar tus configs actuales (por si acaso)
cp .env .env.backup
cp docker-compose.yml docker-compose.yml.backup
cp nginx.conf nginx.conf.backup

# 2. Traer los últimos cambios del repo
git pull origin main

# 3. Si tenés conflictos en .env (porque lo editaste localmente), resolvélos:
#    - git checkout --theirs .env   (usa el del repo)
#    - O manualmente: mantené tus valores y agregá DB_ENCRYPTION_KEY

# 4. Actualizar la imagen en tu .env (si ya existe)
sed -i 's/2026\.4\.15/2026.4.26-slim/g' .env

# 5. Re-ejecutar setup.sh (regenera docker-compose.yml y nginx.conf con lo nuevo)
source venv/bin/activate  # si usás venv para sqlcipher3
./setup.sh

# 6. Bajar los contenedores viejos y levantar los nuevos
docker compose down
docker compose up -d

# 7. Verificar que arrancan
docker compose ps
docker compose logs personal | tail -10
```

**Nota importante:** `docker-compose.yml` y `nginx.conf` se regeneran de cero con `./setup.sh`.
No pierdas tiempo resolviendo conflictos en esos archivos — simplemente sobrescribilos.

(End of file)
