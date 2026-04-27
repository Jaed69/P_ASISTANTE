# OpenClaw Fleet — STATUS

> Este archivo lo actualiza Claude Code al final de CADA sesión.
> Sin esto, la próxima sesión empieza ciega.

---

## Fase actual

**Fase 0 — Correcciones y bugs base** (en curso)

## Última sesión

2026-04-27 — Creación de scripts base de Fase 0 (test-gvisor, entrypoint, db_init, db_helper)

## En curso

- [x] Bug 1 — Nginx subpath routing and single host port exposure
  - setup.sh: genera nginx.conf y servicio nginx, quita puertos por bot
  - add-bot.sh: eliminado argumento `<puerto>`, ya no escribe `${NAME}_PORT`
  - .env.example: eliminadas líneas `_PORT`, actualizados comentarios
- [x] Bug 4 — stop_grace_period: 30s + stop_signal: SIGTERM en cada bot
- [x] Bug 3 — Volume mounts separados: config, workspace, data, skills
- [x] Healthcheck calibrado: interval 60s / timeout 10s / retries 3 / start_period 90s
- [x] Token interpolation fix: valor escrito directamente en docker-compose.yml
- [x] Logging rotation (max-size 10m, max-file 3) y tmpfs /tmp en cada bot
- [x] Imagen fijada a `ghcr.io/openclaw/openclaw:2026.4.15` (no :latest)
- [x] `scripts/test-gvisor.sh` — detección gVisor ARM + fallback cap_drop/AppArmor
  - Tests: runsc instalado → contenedor arranca → V8 JIT funciona → fallback seguro
  - Salida: `runtime.env` con `FLEET_RUNTIME`, `FLEET_SECURITY_OPT`, `FLEET_CAP_DROP`, `FLEET_CAP_ADD`
  - Sintaxis bash validada con `bash -n`
- [x] `scripts/entrypoint.sh` — corre DENTRO del contenedor
  - Orden: WAL checkpoint → activar WAL → integrity check → auto-restore → exec openclaw start
  - Sintaxis bash validada con `bash -n`
- [x] `scripts/db_init.py` — crea `data/fleet.db` con SQLCipher
  - Schema completo: clients, bots, api_usage, gateway_tokens, google_tokens, actions_log, rate_limit_events
  - PRAGMAs en orden correcto: key → busy_timeout → WAL → synchronous → wal_autocheckpoint
  - Idempotente: si fleet.db existe, no toca nada
- [x] `scripts/db_helper.py` — helper obligatorio para toda conexión a fleet.db
  - Única función pública: `open_fleet_db(path)`
  - Lanza `RuntimeError` si `DB_ENCRYPTION_KEY` no está en el entorno

## Commits realizados

- `e230551` — `fix: nginx subpath routing and single host port exposure`
  (Commit inicial del repo. Incluye Bug 1, Bug 3, Bug 4, healthcheck
  calibrado, logging rotation, tmpfs, e imagen fijada a 2026.4.15.)

## Próximo commit

Los siguientes commits están listos para hacerse (scripts creados, pendientes de `git add`):

1. `feat: gvisor arm detection with v8 jit test and cap_drop fallback`
   → `scripts/test-gvisor.sh`
2. `feat: add entrypoint.sh with wal checkpoint before integrity check and auto-restore`
   → `scripts/entrypoint.sh`
3. `feat: add sqlcipher fleet.db schema with wal mode and all tables`
   → `scripts/db_init.py`
4. `feat: add db_helper.py centralized connection opener for all scripts`
   → `scripts/db_helper.py`

## Bloqueado por

- [ ] Ejecutar `scripts/test-gvisor.sh` en entorno con Docker para validar Tests 2-4
      → actualmente solo se validó sintaxis bash; se requiere Docker + imagen OpenClaw
- [ ] Confirmar si OpenClaw `/healthz` requiere Authorization header
      → docker run y test directo
- [ ] Integrar `scripts/test-gvisor.sh` en `setup.sh` (inyectar `runtime:` o `security_opt` en docker-compose.yml)
      → paso siguiente de Opción B
- [ ] Integrar `scripts/entrypoint.sh` en `setup.sh` (agregar `entrypoint:` a cada servicio bot)
      → paso siguiente de Opción B

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

## Notas para Luciel

- Faltan por corregir en Fase 0:
  1. ~~Crear `scripts/test-gvisor.sh`~~ ✅
  2. ~~Crear `scripts/entrypoint.sh`~~ ✅
  3. ~~Crear `scripts/db_init.py` / `db_helper.py`~~ ✅
  4. **Integrar scripts en `setup.sh` y `docker-compose.yml`** ← próximo paso
- Las skills en `claude/skills/` (add-new-bot, diagnose-bot) son documentación
  operativa para Fases 2-4; no requieren implementación en Fase 0.
- Python3 no está disponible en el entorno de desarrollo actual; los scripts Python
  fueron escritos según el briefing pero no se pudo hacer `py_compile`. Validar en VPS.

(End of file)
