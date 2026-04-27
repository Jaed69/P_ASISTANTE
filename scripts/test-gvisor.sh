#!/usr/bin/env bash
# scripts/test-gvisor.sh — Detecta compatibilidad gVisor en ARM y aplica runtime seguro
# Uso: ./scripts/test-gvisor.sh
# Salida: escribe runtime.env en la raíz del proyecto
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNTIME_ENV="$PROJECT_ROOT/runtime.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; }
step()  { echo -e "\n${CYAN}──${NC} $*"; }

IMAGE="${OPENCLAW_IMAGE:-ghcr.io/openclaw/openclaw:2026.4.15}"
RUNTIME=""
SECURITY_OPT=""
CAP_DROP=""
CAP_ADD=""

# ── Test 1: runsc instalado ──────────────────────────────────────────────────
step "Test 1: Verificando runsc en PATH"
if command -v runsc &>/dev/null; then
  info "runsc encontrado: $(command -v runsc)"
else
  warn "runsc NO encontrado → usando fallback runc"
  RUNTIME="runc"
fi

# ── Test 2: Contenedor arranca con runsc ─────────────────────────────────────
if [ -z "$RUNTIME" ]; then
  step "Test 2: Arrancando contenedor con runsc"
  if docker run --rm --runtime=runsc "$IMAGE" echo "ok" &>/dev/null; then
    info "Contenedor arranca correctamente con runsc"
  else
    warn "Contenedor NO arranca con runsc → usando fallback runc"
    RUNTIME="runc"
  fi
fi

# ── Test 3: V8 JIT funciona con runsc ────────────────────────────────────────
if [ -z "$RUNTIME" ]; then
  step "Test 3: Verificando V8 JIT con runsc (mmap PROT_EXEC)"
  JIT_TEST=$(docker run --rm --runtime=runsc "$IMAGE" \
    node -e "console.log(JSON.stringify({test: Math.random(), arr: [1,2,3].map(x => x*2)}))" 2>&1) || JIT_TEST=""

  if echo "$JIT_TEST" | grep -q '"test"'; then
    info "V8 JIT funciona correctamente con runsc"
    RUNTIME="runsc"
  else
    warn "V8 JIT FALLA con runsc → probando fallback con cap_drop"
    RUNTIME="runc"
  fi
fi

# ── Test 4: Fallback con cap_drop + verificación V8 ──────────────────────────
if [ "$RUNTIME" = "runc" ]; then
  step "Test 4: Verificando V8 JIT con fallback de seguridad (cap_drop + apparmor)"

  JIT_FALLBACK=$(docker run --rm \
    --security-opt no-new-privileges:true \
    --security-opt apparmor:docker-default \
    --cap-drop ALL \
    --cap-add CHOWN --cap-add SETUID --cap-add SETGID \
    --cap-add DAC_OVERRIDE --cap-add NET_BIND_SERVICE \
    "$IMAGE" node -e "
      const obj = {};
      for (let i = 0; i < 10000; i++) obj[i] = Math.random() * i;
      const sorted = Object.entries(obj).sort((a,b) => a[1] - b[1]);
      console.log('V8 JIT works:', sorted.length === 10000);
    " 2>&1) || JIT_FALLBACK=""

  if echo "$JIT_FALLBACK" | grep -q "V8 JIT works: true"; then
    info "Fallback funciona: V8 JIT activo con restricciones de seguridad"
    SECURITY_OPT="no-new-privileges:true,apparmor:docker-default"
    CAP_DROP="ALL"
    CAP_ADD="CHOWN,SETUID,SETGID,DAC_OVERRIDE,NET_BIND_SERVICE"
  else
    warn "Fallback CON apparmor bloquea V8 JIT → probando sin AppArmor"

    JIT_UNCONFINED=$(docker run --rm \
      --security-opt no-new-privileges:true \
      --security-opt apparmor:unconfined \
      --cap-drop ALL \
      --cap-add CHOWN --cap-add SETUID --cap-add SETGID \
      --cap-add DAC_OVERRIDE --cap-add NET_BIND_SERVICE \
      "$IMAGE" node -e "
        const obj = {};
        for (let i = 0; i < 10000; i++) obj[i] = Math.random() * i;
        const sorted = Object.entries(obj).sort((a,b) => a[1] - b[1]);
        console.log('V8 JIT works:', sorted.length === 10000);
      " 2>&1) || JIT_UNCONFINED=""

    if echo "$JIT_UNCONFINED" | grep -q "V8 JIT works: true"; then
      warn "V8 JIT funciona SOLO sin AppArmor (menos seguro pero funcional)"
      SECURITY_OPT="no-new-privileges:true,apparmor:unconfined"
      CAP_DROP="ALL"
      CAP_ADD="CHOWN,SETUID,SETGID,DAC_OVERRIDE,NET_BIND_SERVICE"
    else
      error "CRÍTICO: V8 JIT no funciona ni con runsc ni con fallback. Abortando."
      echo ""
      echo "Diagnóstico:"
      echo "  - runsc output: $JIT_TEST"
      echo "  - fallback output: $JIT_FALLBACK"
      echo "  - unconfined output: $JIT_UNCONFINED"
      exit 1
    fi
  fi
fi

# ── Escribir runtime.env ─────────────────────────────────────────────────────
step "Generando runtime.env"

cat > "$RUNTIME_ENV" << EOF
# AUTO-GENERADO por scripts/test-gvisor.sh — NO edites manualmente.
# Re-ejecuta ./scripts/test-gvisor.sh para regenerar.

FLEET_RUNTIME=${RUNTIME}
FLEET_SECURITY_OPT=${SECURITY_OPT}
FLEET_CAP_DROP=${CAP_DROP}
FLEET_CAP_ADD=${CAP_ADD}
EOF

info "runtime.env generado en $RUNTIME_ENV"
echo ""
echo -e "${CYAN}Resumen de seguridad:${NC}"
echo "  Runtime:     $RUNTIME"
if [ -n "$SECURITY_OPT" ]; then
  echo "  Security:    $SECURITY_OPT"
  echo "  Cap drop:    $CAP_DROP"
  echo "  Cap add:     $CAP_ADD"
else
  echo "  Security:    gVisor (runsc) — sandbox completo"
fi
