# Tuning — Otimização de Performance (Single-Node)

Parâmetros de tuning para o ambiente single-node `sles16BBOBS.lab`.
Neste ambiente todos os serviços competem pelos mesmos recursos de CPU,
RAM e I/O — por isso o balanceamento entre componentes é crítico.

Valores de referência baseados em **4 vCPU e 8 GB RAM**.
Ajuste proporcionalmente conforme o hardware disponível.

> **Ambiente de produção multi-servidor:** Ver
> [`obs-sles16-multinode`](https://github.com/mariosergiosl/obs-sles16-multinode)
> — cada componente opera em nó dedicado com tuning independente.

---

## Distribuição de Memória Recomendada (8 GB RAM)

Em single-node todos os serviços compartilham o mesmo pool de memória.
A distribuição abaixo evita que um componente esgote a RAM e provoque
swap — o que degrada drasticamente a performance de todos os serviços.

| Componente | Alocação sugerida | Parâmetro |
|-----------|-------------------|-----------|
| MariaDB (InnoDB Buffer Pool) | 2 GB | `innodb_buffer_pool_size` |
| Redis | 512 MB | `maxmemory` |
| Memcached | 512 MB | `CACHESIZE` |
| Apache + Passenger (processos Ruby) | ~1.5 GB | `PassengerMaxPoolSize` |
| Sistema Operacional + OBS backend | ~1.5 GB | reserva |
| Margem de segurança | ~2 GB | — |

> Nunca deixe o sistema atingir swap em produção. Monitore com
> `free -h` e `vmstat 1 5` regularmente.

---

## MariaDB

Arquivo: `/etc/my.cnf.d/tuning.cnf`

```bash
cat <<EOF > /etc/my.cnf.d/tuning.cnf
[mysqld]

# --- InnoDB Buffer Pool ---
# Single-node: 2 GB (RAM compartilhada com outros servicos)
# Produção dedicada: 60-70% da RAM total do no
innodb_buffer_pool_size      = 2G
innodb_buffer_pool_instances = 2       # 1 instancia por GB

# --- InnoDB Log ---
innodb_log_file_size         = 256M    # maior = menos flush = mais rapido
innodb_log_buffer_size       = 32M
innodb_flush_log_at_trx_commit = 1     # 1=seguro (padrao), 2=mais rapido

# --- I/O ---
innodb_io_capacity           = 400     # ajuste para SSD: 2000-4000
innodb_io_capacity_max       = 800
innodb_read_io_threads       = 4
innodb_write_io_threads      = 4
innodb_flush_method          = O_DIRECT  # evita double buffering com OS cache

# --- Conexoes ---
max_connections              = 150     # pool Rails (10) x frontends + margem
wait_timeout                 = 600
interactive_timeout          = 600
connect_timeout              = 10

# --- Query Cache (desativar — obsoleto no MariaDB 10.4+) ---
query_cache_type             = 0
query_cache_size             = 0

# --- Tabelas temporarias ---
tmp_table_size               = 32M
max_heap_table_size          = 32M

# --- Buffers de Sort e Join ---
sort_buffer_size             = 2M
join_buffer_size             = 2M
read_buffer_size             = 1M
read_rnd_buffer_size         = 1M
EOF
```

**Reiniciar para aplicar:**
```bash
systemctl restart mariadb
```

**Verificar eficiência do buffer pool:**
```bash
mysql -u root -p -e "
  SELECT
    VARIABLE_NAME,
    VARIABLE_VALUE
  FROM information_schema.GLOBAL_STATUS
  WHERE VARIABLE_NAME IN (
    'Innodb_buffer_pool_read_requests',
    'Innodb_buffer_pool_reads',
    'Innodb_buffer_pool_pages_dirty',
    'Innodb_buffer_pool_pages_free'
  );
"
# Taxa de hit esperada: > 99%
# Formula: (read_requests - reads) / read_requests * 100
```

**Verificar conexões ativas:**
```bash
mysql -u root -p -e "SHOW STATUS LIKE 'Threads_connected';"
mysql -u root -p -e "SHOW PROCESSLIST;"
```

---

## Redis

Arquivo: `/etc/redis/default.conf`

```bash
# Editar /etc/redis/default.conf — adicionar ou ajustar os parametros abaixo

# --- Memoria ---
maxmemory            512mb
maxmemory-policy     allkeys-lru     # evicta LRU ao atingir o limite
maxmemory-samples    5               # precisao do LRU (5=padrao, 10=mais preciso)

# --- Persistencia AOF ---
appendonly           yes
appendfilename       "appendonly.aof"
appendfsync          everysec        # equilibrio seguranca/performance
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size   32mb

# --- Rede ---
tcp-backlog          511
timeout              0
tcp-keepalive        300

# --- Slow Log ---
slowlog-log-slower-than 10000        # microsegundos — logar operacoes > 10ms
slowlog-max-len         64

# --- Latencia ---
latency-monitor-threshold 50
```

**Reiniciar para aplicar:**
```bash
systemctl restart redis@default.service
```

**Monitoramento:**
```bash
# Informacoes gerais de memoria e uso
redis-cli -u redis://127.0.0.1:6379 info memory
redis-cli -u redis://127.0.0.1:6379 info stats

# Verificar operacoes lentas
redis-cli -u redis://127.0.0.1:6379 slowlog get 10

# Verificar uso de memoria em tempo real
redis-cli -u redis://127.0.0.1:6379 --stat

# Taxa de hit (esperado > 90%)
redis-cli -u redis://127.0.0.1:6379 info stats | grep -E \
  "keyspace_hits|keyspace_misses"
```

---

## Memcached

Arquivo: `/etc/sysconfig/memcached`

```bash
cat <<EOF > /etc/sysconfig/memcached
# Interface de escuta
MEMCACHED_PARAMS="-l 127.0.0.1"

# Porta padrao
PORT="11211"

# Usuario de execucao
USER="memcached"

# Memoria alocada (MB) — single-node: 512 MB
CACHESIZE="512"

# Conexoes simultaneas maximas
MAXCONN="512"

# Threads de processamento — 1 por vCPU
# Para single-node com 4 vCPU compartilhados: 2
MEMCACHED_PARAMS="${MEMCACHED_PARAMS} -t 2"
EOF
```

**Reiniciar para aplicar:**
```bash
systemctl restart memcached.service
```

**Monitoramento:**
```bash
# Estatisticas gerais
echo "stats" | nc 127.0.0.1 11211

# Verificar parametros criticos
echo "stats" | nc 127.0.0.1 11211 | grep -E \
  "limit_maxbytes|bytes |curr_items|evictions|get_hits|get_misses"

# evictions > 0 significa que maxmemory esta baixo — aumentar CACHESIZE
# get_hits / (get_hits + get_misses) = taxa de acerto (esperado > 85%)
```

---

## Apache + Passenger (Frontend)

Arquivo: `/etc/apache2/conf.d/tuning.conf`

```bash
cat <<EOF > /etc/apache2/conf.d/tuning.conf
# --- MPM Event ---
<IfModule mpm_event_module>
    StartServers             2
    MinSpareThreads          10
    MaxSpareThreads          30
    ThreadLimit              32
    ThreadsPerChild          16
    MaxRequestWorkers        64     # single-node: menor que produção dedicada
    MaxConnectionsPerChild   500
</IfModule>

# --- KeepAlive ---
KeepAlive On
KeepAliveTimeout 5
MaxKeepAliveRequests 100

# --- Timeouts ---
Timeout 120

# --- Compressao ---
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/html text/plain text/xml
    AddOutputFilterByType DEFLATE text/css application/javascript
    AddOutputFilterByType DEFLATE application/json application/xml
</IfModule>
EOF
```

**Passenger — em `/etc/apache2/conf.d/passenger.conf`:**

```apache
LoadModule passenger_module /usr/lib64/apache2/mod_passenger.so
<IfModule mod_passenger.c>
  PassengerRoot              /etc/passenger/locations.ini
  PassengerDefaultRuby       /usr/bin/ruby.ruby3.4

  # Single-node: menos processos para nao consumir RAM dos outros servicos
  PassengerMaxPoolSize        4      # processos Ruby (~200 MB cada = ~800 MB total)
  PassengerMinInstances       1      # manter 1 sempre ativo
  PassengerMaxRequests        500    # reiniciar worker apos N requests
  PassengerPoolIdleTime       120    # segundos antes de matar worker ocioso
  PassengerMaxPreloaderIdleTime 0    # desativar preloader em single-node
</IfModule>
```

**Reiniciar para aplicar:**
```bash
apachectl configtest && systemctl restart apache2.service
```

**Monitoramento:**
```bash
# Status do Apache (requer mod_status)
curl -s http://localhost/server-status?auto | grep -E \
  "BusyWorkers|IdleWorkers|ReqPerSec|BytesPerSec"

# Processos Passenger
passenger-status --show=pool 2>/dev/null || \
  echo "passenger-status nao disponivel — verificar instalacao"

# Memoria dos processos Ruby
ps aux | grep -E "(ruby|passenger)" | awk '{sum+=$6} END {print sum/1024 " MB"}'
```

---

## OBS Backend (Daemons)

Os daemons de backend do OBS não têm arquivos de configuração de tuning
tão granulares quanto os outros serviços, mas alguns parâmetros em
`/usr/lib/obs/server/BSConfig.pm` influenciam a performance.

```bash
# Ver configuracoes atuais relevantes
grep -E "maxchild|parallel|timeout" /usr/lib/obs/server/BSConfig.pm

# Monitoramento dos daemons
tail -f /srv/obs/log/dispatcher.log   # fila de builds
tail -f /srv/obs/log/src_server.log   # source server
tail -f /srv/obs/log/rep_server.log   # repository server

# Saude da fila de jobs Rails
sudo -u wwwrun RAILS_ENV=production \
  /srv/www/obs/api/bin/rails runner \
  "puts \"Pending jobs: #{Delayed::Job.count}\""
```

---

## Sistema Operacional

Arquivo: `/etc/sysctl.d/99-obs-tuning.conf`

```bash
cat <<EOF > /etc/sysctl.d/99-obs-tuning.conf
# --- Rede ---
# Backlog de conexoes TCP
net.core.somaxconn             = 4096
net.ipv4.tcp_max_syn_backlog   = 4096

# Buffers de rede
net.core.rmem_max              = 16777216
net.core.wmem_max              = 16777216
net.ipv4.tcp_rmem              = 4096 65536 16777216
net.ipv4.tcp_wmem              = 4096 32768 16777216

# TIME_WAIT — single-node gera muitas conexoes locais
net.ipv4.tcp_tw_reuse          = 1
net.ipv4.tcp_fin_timeout       = 20

# --- Arquivos ---
fs.file-max                    = 524288

# --- VM ---
# Reduzir tendencia de usar swap (0=nunca, 60=padrao, 100=agressivo)
vm.swappiness                  = 10

# Dirty pages — equilibrio entre performance e seguranca de dados
vm.dirty_ratio                 = 15
vm.dirty_background_ratio      = 5
EOF

# Aplicar sem reiniciar
sysctl -p /etc/sysctl.d/99-obs-tuning.conf
```

**Limites de arquivos por processo:**

```bash
cat <<EOF >> /etc/security/limits.conf
# OBS single-node — limites de arquivo aberto
obsrun  soft  nofile  32768
obsrun  hard  nofile  32768
wwwrun  soft  nofile  32768
wwwrun  hard  nofile  32768
mysql   soft  nofile  32768
mysql   hard  nofile  32768
redis   soft  nofile  32768
redis   hard  nofile  32768
EOF
```

---

## Checklist de Monitoramento Contínuo

Execute periodicamente para identificar gargalos antes que causem problemas:

```bash
# Uso geral de recursos
top -b -n 1 | head -20
free -h
df -h /srv /var/lib/mysql

# Verificar swap em uso (deve ser 0 ou proximo de 0)
free -h | grep Swap

# I/O por dispositivo
iostat -x 1 3

# Conexoes de rede ativas por servico
ss -tulpn | grep -E ':(80|443|3306|6379|11211|5252|5352)'

# Status de todos os servicos OBS
systemctl status \
  redis@default.service \
  obsredis.service \
  obssrcserver.service \
  obsrepserver.service \
  obsdispatcher.service \
  mariadb.service \
  memcached.service \
  apache2.service

# MariaDB — conexoes e queries lentas
mysql -u root -p -e "SHOW STATUS LIKE 'Threads_connected';"
mysql -u root -p -e "SHOW STATUS LIKE 'Slow_queries';"

# Redis — memoria e evictions
redis-cli -u redis://127.0.0.1:6379 info memory | grep -E \
  "used_memory_human|maxmemory_human|mem_fragmentation_ratio"

# Fila de jobs OBS
sudo -u wwwrun RAILS_ENV=production \
  /srv/www/obs/api/bin/rails runner \
  "puts \"Jobs pendentes: #{Delayed::Job.count}\""
```
