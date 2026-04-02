#!/bin/bash
# =============================================================================
# verify-services.sh — Verificação de Saúde do Stack OBS
# =============================================================================
# Uso: bash scripts/verify-services.sh
#
# Verifica o estado de todos os serviços do OBS e exibe um resumo.
# =============================================================================

set -uo pipefail

PASS=0
FAIL=0
WARN=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_service() {
    local name="$1"
    local unit="$2"
    if systemctl is-active --quiet "${unit}"; then
        echo -e "  ${GREEN}[OK]${NC}   ${name} (${unit})"
        ((PASS++))
    else
        local state
        state=$(systemctl is-active "${unit}" 2>/dev/null || echo "not-found")
        echo -e "  ${RED}[FAIL]${NC} ${name} (${unit}) — ${state}"
        ((FAIL++))
    fi
}

check_port() {
    local desc="$1"
    local port="$2"
    if ss -tlnp | grep -q ":${port}"; then
        echo -e "  ${GREEN}[OK]${NC}   Porta ${port}/tcp em escuta (${desc})"
        ((PASS++))
    else
        echo -e "  ${RED}[FAIL]${NC} Porta ${port}/tcp NÃO encontrada (${desc})"
        ((FAIL++))
    fi
}

check_url() {
    local desc="$1"
    local url="$2"
    local http_code
    http_code=$(curl -sk -o /dev/null -w "%{http_code}" "${url}" 2>/dev/null || echo "000")
    if [[ "${http_code}" =~ ^(200|301|302|401|403)$ ]]; then
        echo -e "  ${GREEN}[OK]${NC}   ${desc} → HTTP ${http_code}"
        ((PASS++))
    else
        echo -e "  ${RED}[FAIL]${NC} ${desc} → HTTP ${http_code}"
        ((FAIL++))
    fi
}

echo "======================================================="
echo " OBS Stack — Verificação de Saúde"
echo " $(date)"
echo "======================================================="

echo
echo "--- Cache / Fila ---"
check_service "Redis"         "redis@default.service"
check_service "OBS Redis FWD" "obsredis.service"
check_service "Memcached"     "memcached.service"

echo
echo "--- Backend ---"
check_service "Source Server"    "obssrcserver.service"
check_service "Repo Server"      "obsrepserver.service"
check_service "Dispatcher"       "obsdispatcher.service"
check_service "Publisher"        "obspublisher.service"
check_service "Scheduler"        "obsscheduler.service"
check_service "Worker"           "obsworker.service"

echo
echo "--- Frontend ---"
check_service "MariaDB"          "mariadb.service"
check_service "Apache"           "apache2.service"
check_service "API Support"      "obs-api-support.target"

echo
echo "--- Portas ---"
check_port "Redis"       "6379"
check_port "MariaDB"     "3306"
check_port "HTTP"        "80"
check_port "HTTPS"       "443"

echo
echo "--- Endpoints ---"
check_url "HTTPS Frontend" "https://localhost/"

echo
echo "--- SELinux ---"
MODE=$(getenforce 2>/dev/null || echo "Desconhecido")
echo -e "  ${YELLOW}[INFO]${NC} SELinux mode: ${MODE}"
DENIED=$(grep -c "denied" /var/log/audit/audit.log 2>/dev/null || echo "0")
if [[ "${DENIED}" -eq 0 ]]; then
    echo -e "  ${GREEN}[OK]${NC}   Nenhuma negação em audit.log"
    ((PASS++))
else
    echo -e "  ${YELLOW}[WARN]${NC} ${DENIED} entrada(s) 'denied' em audit.log — verifique"
    ((WARN++))
fi

echo
echo "======================================================="
echo -e " RESULTADO: ${GREEN}${PASS} OK${NC} | ${RED}${FAIL} FALHA${NC} | ${YELLOW}${WARN} AVISO${NC}"
echo "======================================================="

if [[ "${FAIL}" -gt 0 ]]; then
    echo
    echo "Consulte docs/12-troubleshooting.md para diagnóstico."
    exit 1
fi
exit 0
