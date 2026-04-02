#!/bin/bash
#===============================================================================
#
# FILE: apply-selinux-policy.sh
#
# USAGE: apply-selinux-policy.sh
#
# DESCRIPTION: Compiles and installs the SELinux policy modules required
#              for the OBS (Open Build Service) on SLES 16.
#
#              Covers two independent groups of SELinux blocks identified
#              during lab provisioning:
#
#              Group 1 - obsredis:
#                Allows bs_redis (init_t) to create and manipulate the
#                FIFO .ping file in /srv/obs/events/redis/ (var_t context).
#
#              Group 2 - obs-apache:
#                Allows Apache (httpd_t) to execute Ruby binaries with
#                httpd_sys_content_t context (Passenger / Rails API).
#                Also configures port 82, TLS context and httpd booleans.
#
# OPTIONS:
#    -h, --help      Display this help message
#    -v, --version   Display script version
#
# REQUIREMENTS: checkmodule, semodule_package, semodule, semanage, setsebool
#
# BUGS: ---
#
# NOTES: Run this script BEFORE starting any OBS backend or frontend service.
#        Without these policies, services fail immediately with status=13 (EACCES).
#        Reference: docs/06-selinux.md
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

# --- CONFIG ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="${SCRIPT_DIR}/../configs/selinux"
WORK_DIR="/tmp/obs-selinux"

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

Compiles and installs SELinux policy modules for OBS on SLES 16.
Covers: obsredis (backend) and obs-apache (frontend).

OPTIONS:
  -h, --help      Display this help message
  -v, --version   Display script version

Examples:
  $0
  $0 --help
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
# NAME: log_ok
# DESCRIPTION: Prints a success message in green.
# PARAMETER 1: Message string
# ------------------------------------------------------------------------------
log_ok() {
    echo -e "  ${GREEN}[OK]${NC}   $*"
}

# ------------------------------------------------------------------------------
# NAME: log_fail
# DESCRIPTION: Prints an error message in red and exits.
# PARAMETER 1: Message string
# ------------------------------------------------------------------------------
log_fail() {
    echo -e "  ${RED}[FAIL]${NC} $*"
    exit 1
}

# ------------------------------------------------------------------------------
# NAME: log_info
# DESCRIPTION: Prints an informational message in yellow.
# PARAMETER 1: Message string
# ------------------------------------------------------------------------------
log_info() {
    echo -e "  ${YELLOW}[INFO]${NC} $*"
}

# ------------------------------------------------------------------------------
# NAME: install_module
# DESCRIPTION: Compiles, packages and installs a SELinux policy module from
#              a .te source file located in configs/selinux/.
# PARAMETER 1: Module name (without extension, e.g. "obsredis")
# ------------------------------------------------------------------------------
install_module() {
    local name="$1"
    local te_file="${CONFIGS_DIR}/${name}.te"

    echo "--- Module: ${name} ---"

    if [[ ! -f "${te_file}" ]]; then
        log_fail "Source file not found: ${te_file}"
    fi

    cp "${te_file}" "${WORK_DIR}/${name}.te"

    echo -n "  Compiling .te -> .mod ... "
    checkmodule -M -m \
        -o "${WORK_DIR}/${name}.mod" \
        "${WORK_DIR}/${name}.te" 2>/dev/null \
        && echo "done" || log_fail "Compilation failed for ${name}.te"

    echo -n "  Packaging .mod -> .pp  ... "
    semodule_package \
        -o "${WORK_DIR}/${name}.pp" \
        -m "${WORK_DIR}/${name}.mod" 2>/dev/null \
        && echo "done" || log_fail "Packaging failed for ${name}.mod"

    echo -n "  Installing into kernel ... "
    semodule -i "${WORK_DIR}/${name}.pp" 2>/dev/null \
        && echo "done" || log_fail "Installation failed for ${name}.pp"

    if semodule -l | grep -q "^${name}"; then
        log_ok "Module '${name}' installed successfully."
    else
        log_fail "Module '${name}' not found after installation."
    fi

    echo
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
# STEP 1: PRE-FLIGHT CHECKS
# ------------------------------------------------------------------------------
echo "----------------------------------------------------------------"
echo ">>> STEP 1: PRE-FLIGHT CHECKS"
echo "----------------------------------------------------------------"

if ! sestatus 2>/dev/null | grep -q "enabled"; then
    log_info "SELinux is not enabled on this system. Exiting."
    exit 0
fi

MODE=$(getenforce)
log_info "SELinux current mode: ${MODE}"
echo

mkdir -p "${WORK_DIR}"

# ------------------------------------------------------------------------------
# STEP 2: GROUP 1 — obsredis POLICY (Backend)
# ------------------------------------------------------------------------------
echo "----------------------------------------------------------------"
echo ">>> STEP 2: GROUP 1 — obsredis (backend / bs_redis)"
echo "----------------------------------------------------------------"
echo
install_module "obsredis"

# ------------------------------------------------------------------------------
# STEP 3: GROUP 2 — obs-apache POLICY (Frontend)
# ------------------------------------------------------------------------------
echo "----------------------------------------------------------------"
echo ">>> STEP 3: GROUP 2 — obs-apache (frontend / Apache + Passenger)"
echo "----------------------------------------------------------------"
echo
install_module "obs-apache"

# ------------------------------------------------------------------------------
# STEP 4: APACHE BOOLEANS
# ------------------------------------------------------------------------------
echo "----------------------------------------------------------------"
echo ">>> STEP 4: APACHE SELINUX BOOLEANS"
echo "----------------------------------------------------------------"
echo

for bool in httpd_can_network_connect httpd_can_network_relay httpd_execmem; do
    echo -n "  setsebool -P ${bool} 1 ... "
    setsebool -P "${bool}" 1 \
        && log_ok "${bool} enabled." \
        || log_fail "Failed to set ${bool}."
done

echo

# ------------------------------------------------------------------------------
# STEP 5: PORT 82/tcp MAPPING
# ------------------------------------------------------------------------------
echo "----------------------------------------------------------------"
echo ">>> STEP 5: PORT 82/tcp — http_port_t MAPPING"
echo "----------------------------------------------------------------"
echo

if semanage port -l 2>/dev/null | grep -q "^http_port_t.*tcp.*\b82\b"; then
    log_info "Port 82/tcp already mapped as http_port_t — skipping."
else
    echo -n "  semanage port -a -t http_port_t -p tcp 82 ... "
    semanage port -a -t http_port_t -p tcp 82 \
        && log_ok "Port 82/tcp mapped as http_port_t." \
        || log_fail "Failed to map port 82/tcp."
fi

echo

# ------------------------------------------------------------------------------
# STEP 6: TLS CERTIFICATE CONTEXT
# ------------------------------------------------------------------------------
echo "----------------------------------------------------------------"
echo ">>> STEP 6: TLS CERTIFICATE — cert_t CONTEXT"
echo "----------------------------------------------------------------"
echo

if [[ -d /srv/obs/certs ]]; then
    echo -n "  chcon -R -t cert_t /srv/obs/certs/ ... "
    chcon -R -t cert_t /srv/obs/certs/ \
        && log_ok "Context cert_t applied to /srv/obs/certs/." \
        || log_fail "Failed to apply cert_t context."
else
    log_info "/srv/obs/certs/ not found. Run after generating the TLS certificate."
fi

echo

# ------------------------------------------------------------------------------
# STEP 7: RUBY BINARIES CONTEXT
# ------------------------------------------------------------------------------
echo "----------------------------------------------------------------"
echo ">>> STEP 7: RUBY BINARIES — bin_t CONTEXT"
echo "----------------------------------------------------------------"
echo

for bin in /srv/www/obs/api/bin/clockworkd /srv/www/obs/api/bin/delayed_job; do
    if [[ -f "${bin}" ]]; then
        echo -n "  chcon -t bin_t $(basename ${bin}) ... "
        chcon -t bin_t "${bin}" \
            && log_ok "Context bin_t applied to $(basename ${bin})." \
            || log_fail "Failed to apply bin_t to $(basename ${bin})."
    else
        log_info "$(basename ${bin}) not found. Run after installing obs-api."
    fi
done

echo

# ------------------------------------------------------------------------------
# GRAND FINALE
# ------------------------------------------------------------------------------
echo "================================================================"
echo "   GRAND FINALE: SUCCESS!"
echo "   All SELinux policies applied."
echo "================================================================"
echo
echo "   Installed modules:"
semodule -l | grep "^obs" || log_info "No obs modules listed — verify manually."
echo
echo "   Next steps:"
echo "     systemctl restart obsredis.service"
echo "     systemctl restart apache2.service"
echo "================================================================"
