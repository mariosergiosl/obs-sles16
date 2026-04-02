#!/bin/bash
#===============================================================================
#
# FILE: verify-services.sh
#
# USAGE: verify-services.sh
#
# DESCRIPTION: Verifies the health of the full OBS stack on SLES 16.
#              Checks systemd service status, listening ports, HTTP endpoint
#              and SELinux audit log for recent denials.
#
#              Covers:
#                - Cache / Queue  : Redis, obsredis, Memcached
#                - Backend        : obssrcserver, obsrepserver, obsdispatcher,
#                                   obspublisher, obsscheduler, obsworker
#                - Frontend       : MariaDB, Apache, obs-api-support
#                - Ports          : 6379, 3306, 80, 443
#                - Endpoint       : https://localhost/
#                - SELinux        : recent denials in audit.log
#
# OPTIONS:
#    -h, --help      Display this help message
#    -v, --version   Display script version
#
# REQUIREMENTS: systemctl, ss, curl, grep, sestatus
#
# BUGS: ---
#
# NOTES: Run as root or with sudo for full SELinux audit log access.
#        Reference: docs/09-verificacao.md
#        Troubleshooting: docs/12-troubleshooting.md
#
# AUTHOR:
#    Mario Luz (ml), mario.mssl[at]gmail.com
#
# COMPANY: ---
#
# VERSION: 1.0
# CREATED: 2026-04-02
# REVISION: ---
#
#===============================================================================

set -e

SCRIPT_VERSION="1.0"

# --- COUNTERS ---
PASS=0
FAIL=0
WARN=0

# --- COLORS ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ------------------------------------------------------------------------------
# NAME: show_help
# DESCRIPTION: Displays usage instructions and available options.
# PARAMETER: None
# ------------------------------------------------------------------------------
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Verifies the health of the full OBS stack on SLES 16.
Checks services, ports, HTTP endpoint and SELinux denials.

OPTIONS:
  -h, --help      Display this help message
  -v, --version   Display script version

Examples:
  $0
  sudo $0
EOF
}

# ------------------------------------------------------------------------------
# NAME: show_version
# DESCRIPTION: Displays the current version of the script.
# PARAMETER: None
# ------------------------------------------------------------------------------
show_version() {
    echo "$0 version $SCRIPT_VERSION"
}

# ------------------------------------------------------------------------------
# NAME: check_service
# DESCRIPTION: Checks if a systemd service unit is active (running).
#              Increments global PASS or FAIL counter accordingly.
# PARAMETER 1: Human-readable service label
# PARAMETER 2: Systemd unit name (e.g. redis@default.service)
# ------------------------------------------------------------------------------
check_service() {
    local label="$1"
    local unit="$2"

    if systemctl is-active --quiet "${unit}"; then
        echo -e "  ${GREEN}[OK]${NC}   ${label} (${unit})"
        ((PASS++))
    else
        local state
        state=$(systemctl is-active "${unit}" 2>/dev/null || echo "not-found")
        echo -e "  ${RED}[FAIL]${NC} ${label} (${unit}) — ${state}"
        echo "         Run: journalctl -xeu ${unit}"
        ((FAIL++))
    fi
}

# ------------------------------------------------------------------------------
# NAME: check_port
# DESCRIPTION: Checks if a TCP port is in LISTEN state.
#              Increments global PASS or FAIL counter accordingly.
# PARAMETER 1: Port description label
# PARAMETER 2: Port number
# ------------------------------------------------------------------------------
check_port() {
    local desc="$1"
    local port="$2"

    if ss -tlnp | grep -q ":${port}"; then
        echo -e "  ${GREEN}[OK]${NC}   Port ${port}/tcp listening (${desc})"
        ((PASS++))
    else
        echo -e "  ${RED}[FAIL]${NC} Port ${port}/tcp NOT listening (${desc})"
        ((FAIL++))
    fi
}

# ------------------------------------------------------------------------------
# NAME: check_url
# DESCRIPTION: Checks if an HTTP/HTTPS endpoint returns a valid response code.
#              Accepts 200, 301, 302, 401, 403 as valid (application is up).
# PARAMETER 1: Human-readable endpoint label
# PARAMETER 2: Full URL to check
# ------------------------------------------------------------------------------
check_url() {
    local desc="$1"
    local url="$2"
    local http_code

    http_code=$(curl -sk -o /dev/null -w "%{http_code}" "${url}" 2>/dev/null || echo "000")

    if [[ "${http_code}" =~ ^(200|301|302|401|403)$ ]]; then
        echo -e "  ${GREEN}[OK]${NC}   ${desc} — HTTP ${http_code}"
        ((PASS++))
    else
        echo -e "  ${RED}[FAIL]${NC} ${desc} — HTTP ${http_code}"
        echo "         Run: curl -Ik ${url}"
        ((FAIL++))
    fi
}

# ------------------------------------------------------------------------------
# Argument Parsing
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--version)
            show_version
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# ------------------------------------------------------------------------------
# HEADER
# ------------------------------------------------------------------------------
echo "================================================================"
echo "   OBS Stack — Health Check"
echo "   $(date)"
echo "================================================================"

# ------------------------------------------------------------------------------
# STEP 1: CACHE / QUEUE SERVICES
# ------------------------------------------------------------------------------
echo
echo "----------------------------------------------------------------"
echo ">>> STEP 1: CACHE / QUEUE"
echo "----------------------------------------------------------------"
check_service "Redis"           "redis@default.service"
check_service "OBS Redis FWD"   "obsredis.service"
check_service "Memcached"       "memcached.service"

# ------------------------------------------------------------------------------
# STEP 2: BACKEND SERVICES
# ------------------------------------------------------------------------------
echo
echo "----------------------------------------------------------------"
echo ">>> STEP 2: BACKEND"
echo "----------------------------------------------------------------"
check_service "Source Server"   "obssrcserver.service"
check_service "Repo Server"     "obsrepserver.service"
check_service "Dispatcher"      "obsdispatcher.service"
check_service "Publisher"       "obspublisher.service"
check_service "Scheduler"       "obsscheduler.service"
check_service "Worker"          "obsworker.service"

# ------------------------------------------------------------------------------
# STEP 3: FRONTEND SERVICES
# ------------------------------------------------------------------------------
echo
echo "----------------------------------------------------------------"
echo ">>> STEP 3: FRONTEND"
echo "----------------------------------------------------------------"
check_service "MariaDB"         "mariadb.service"
check_service "Apache"          "apache2.service"
check_service "API Support"     "obs-api-support.target"

# ------------------------------------------------------------------------------
# STEP 4: LISTENING PORTS
# ------------------------------------------------------------------------------
echo
echo "----------------------------------------------------------------"
echo ">>> STEP 4: PORTS"
echo "----------------------------------------------------------------"
check_port "Redis"      "6379"
check_port "MariaDB"    "3306"
check_port "HTTP"       "80"
check_port "HTTPS"      "443"

# ------------------------------------------------------------------------------
# STEP 5: HTTP ENDPOINT
# ------------------------------------------------------------------------------
echo
echo "----------------------------------------------------------------"
echo ">>> STEP 5: HTTP ENDPOINT"
echo "----------------------------------------------------------------"
check_url "HTTPS Frontend" "https://localhost/"

# ------------------------------------------------------------------------------
# STEP 6: SELINUX
# ------------------------------------------------------------------------------
echo
echo "----------------------------------------------------------------"
echo ">>> STEP 6: SELINUX"
echo "----------------------------------------------------------------"

SEL_MODE=$(getenforce 2>/dev/null || echo "Unknown")
echo -e "  ${YELLOW}[INFO]${NC} SELinux mode: ${SEL_MODE}"

DENIED=$(grep -c "denied" /var/log/audit/audit.log 2>/dev/null || echo "0")

if [[ "${DENIED}" -eq 0 ]]; then
    echo -e "  ${GREEN}[OK]${NC}   No denials found in audit.log."
    ((PASS++))
else
    echo -e "  ${YELLOW}[WARN]${NC} ${DENIED} denial(s) in audit.log — review recommended."
    echo "         Run: grep -i denied /var/log/audit/audit.log | tail -20"
    ((WARN++))
fi

# ------------------------------------------------------------------------------
# GRAND FINALE
# ------------------------------------------------------------------------------
echo
echo "================================================================"
echo "   GRAND FINALE: Health Check Complete"
echo "================================================================"
echo -e "   ${GREEN}${PASS} OK${NC}  |  ${RED}${FAIL} FAIL${NC}  |  ${YELLOW}${WARN} WARN${NC}"
echo "================================================================"

if [[ "${FAIL}" -gt 0 ]]; then
    echo
    echo "   One or more checks failed."
    echo "   Reference: docs/12-troubleshooting.md"
    exit 1
fi

exit 0
