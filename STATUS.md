# OpenClaw Fleet — STATUS

> Este archivo lo actualiza Claude Code al final de CADA sesión.
> Sin esto, la próxima sesión empieza ciega.

---

## Fase actual

**Fase 0 — Correcciones y bugs base** (en curso)

## Última sesión

2026-04-27 — Sesión de inicio de Fase 0

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

## Próximo commit

`fix: nginx subpath routing and single host port exposure`
(Incluye Bug 1, Bug 3, Bug 4, y healthcheck calibrado en un solo commit
porque están intrínsecamente ligados en la generación del docker-compose.yml)

## Bloqueado por

- [ ] Verificar compatibilidad de gVisor (`runsc`) con OpenClaw 2026.4.15 en ARM
      → resolver en script `test-gvisor.sh` durante Fase 0
- [ ] Confirmar si OpenClaw `/healthz` requiere Authorization header
      → docker run y test directo

## Decisiones tomadas en sesión

- El repositorio no tenía `.env.example` al inicio de la sesión, pero apareció
  después de la primera interacción. Se actualizó para reflejar la nueva
  arquitectura sin puertos por bot.
- Se unificaron los fixes del compose en un solo commit porque `setup.sh`
  genera todo de una pieza.

## Notas para Luciel

- Faltan por corregir en Fase 0:
  1. Crear `scripts/test-gvisor.sh` (gVisor ARM detection + cap_drop fallback)
  2. Crear `scripts/entrypoint.sh` (WAL mode + integrity check + auto-restore)
  3. Crear `scripts/db_init.py` / `db_helper.py` para fleet.db con SQLCipher
- Las skills en `claude/skills/` (add-new-bot, diagnose-bot) son documentación
  operativa para Fases 2-4; no requieren implementación en Fase 0.
