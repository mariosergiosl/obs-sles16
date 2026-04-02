#!/bin/bash
# =============================================================================
# apply-selinux-policy.sh — Aplica a Política SELinux Consolidada do OBS
# =============================================================================
# Uso: bash scripts/apply-selinux-policy.sh
#
# Executa a compilação e instalação do módulo obsredis_final.te em uma
# única operação, sem processo iterativo.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TE_FILE="${SCRIPT_DIR}/../configs/selinux/obsredis_final.te"
WORK_DIR="/tmp/obs-selinux"

echo "=== Política SELinux OBS — Instalação ==="
echo

# Verificar se SELinux está ativo
if ! sestatus | grep -q "enabled"; then
    echo "[AVISO] SELinux não está habilitado neste sistema. Script encerrado."
    exit 0
fi

# Verificar modo
MODE=$(getenforce)
echo "[INFO] SELinux mode atual: ${MODE}"
echo

# Criar diretório de trabalho
mkdir -p "${WORK_DIR}"

# Copiar arquivo de política
cp "${TE_FILE}" "${WORK_DIR}/obsredis_final.te"

echo "[1/3] Compilando módulo de política..."
checkmodule -M -m \
    -o "${WORK_DIR}/obsredis_final.mod" \
    "${WORK_DIR}/obsredis_final.te"

echo "[2/3] Empacotando módulo..."
semodule_package \
    -o "${WORK_DIR}/obsredis_final.pp" \
    -m "${WORK_DIR}/obsredis_final.mod"

echo "[3/3] Instalando módulo no kernel..."
semodule -i "${WORK_DIR}/obsredis_final.pp"

echo
echo "=== Verificação ==="
if semodule -l | grep -q "obsredis_final"; then
    echo "[OK] Módulo obsredis_final instalado com sucesso."
    semodule -l | grep obsredis
else
    echo "[ERRO] Módulo não encontrado após instalação. Verifique manualmente."
    exit 1
fi

echo
echo "=== Booleans do Apache ==="
setsebool -P httpd_can_network_connect 1
setsebool -P httpd_can_network_relay   1
setsebool -P httpd_execmem             1
echo "[OK] Booleans configurados."

echo
echo "=== Mapeamento de Porta 82/tcp ==="
if ! semanage port -l | grep -q "82"; then
    semanage port -a -t http_port_t -p tcp 82
    echo "[OK] Porta 82/tcp mapeada como http_port_t."
else
    echo "[INFO] Porta 82/tcp já mapeada — nenhuma ação necessária."
fi

echo
echo "=== Concluído ==="
echo "Reinicie os serviços de backend para aplicar as novas permissões:"
echo "  systemctl restart obsredis.service"
