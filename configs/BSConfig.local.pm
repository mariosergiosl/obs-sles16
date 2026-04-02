package BSConfig;

# =============================================================================
# BSConfig.local.pm — Configuração Local do Backend OBS
# =============================================================================
# Este arquivo sobrescreve seletivamente as variáveis de BSConfig.pm.
# Persiste em atualizações do pacote obs-server (ao contrário de BSConfig.pm).
#
# Destino: /usr/lib/obs/server/BSConfig.local.pm
# Permissões: obsrun:obsrun 644
#
# Instalação:
#   cp configs/BSConfig.local.pm /usr/lib/obs/server/BSConfig.local.pm
#   chown obsrun:obsrun /usr/lib/obs/server/BSConfig.local.pm
#   chmod 644 /usr/lib/obs/server/BSConfig.local.pm
# =============================================================================

# -----------------------------------------------------------------------------
# Redis Server
# OBS Unstable (SLES 16): variável 'redisserver' (sem sublinhado), URI redis://
#
# Lab:      redis://127.0.0.1:6379
# Produção: redis://<IP-DEDICADO>:6379
#           Com autenticação: redis://:<SENHA>@<IP>:6379
# -----------------------------------------------------------------------------
$redisserver = 'redis://127.0.0.1:6379';

# -----------------------------------------------------------------------------
# Source Server e Repository Server (apenas para nós Worker remotos)
# Descomente e ajuste em topologia descentralizada.
#
# our $srcserver  = 'http://<IP-BACKEND>:5252';
# our $reposerver = 'http://<IP-BACKEND>:5352';
# -----------------------------------------------------------------------------

1;
