# 12 — Troubleshooting

Registro de incidentes identificados durante o provisionamento no laboratório, com causas e vetores de resolução.

---

## Matriz de Incidentes

| ID | Sintoma / Erro | Camada | Causa Raiz | Resolução |
|----|---------------|--------|------------|-----------|
| T01 | `nothing provides 'ghostscript-fonts-std'` | Dependência de pacote | Módulo `sle-module-desktop-applications` não existe no SLES 16 | Ativar SUSE Package Hub: `SUSEConnect -p PackageHub/16.0/x86_64` |
| T02 | `SUSEConnect` retorna erro 422 no módulo desktop | Registro SCC | Módulo renomeado/reestruturado no SLES 16 | Usar PackageHub em vez do módulo desktop |
| T03 | `/usr/sbin/obs-api-setup: No such file or directory` | Instalação | Binário exclusivo do OBS Appliance; não existe em instalações via repositório | Provisionar manualmente via `mysql` + `rake db:setup` |
| T04 | `Unit obs-server.service does not exist` | Backend | Arquitetura modular — não há serviço monolítico | Usar unidades individuais: `obssrcserver`, `obsrepserver`, etc. |
| T05 | `obsredis.service: Failed — status=13` | SELinux (MAC) | Política SELinux não permite que `bs_redis` (domínio `init_t`) crie FIFO em diretório com contexto `var_t` | Aplicar módulo `obsredis_final.pp` (ver [06 — SELinux](06-selinux.md)) |
| T06 | `Unit redis.service does not exist` | Systemd | No SLES 16, Redis usa instâncias: `redis@.service` | Usar `systemctl enable --now redis@default.service` |
| T07 | `redis@default.service`: `can't open config file '/etc/redis/default.conf'` | Configuração | Template não copiado automaticamente na instalação | `cp /etc/redis/redis.default.conf.template /etc/redis/default.conf && chown redis:redis /etc/redis/default.conf` |
| T08 | `obsredis.service: Failed — status=29 / "No redis server configured"` | Aplicação (Perl) | Variável `$redis_server` renomeada para `$redisserver` (sem sublinhado) e formato exige URI `redis://` | Criar `BSConfig.local.pm` com `$redisserver = 'redis://127.0.0.1:6379';` |
| T09 | `Permission denied on clockworkd` | Permissão (DAC) | Bit de execução ausente no binário Ruby | `chmod +x /srv/www/obs/api/bin/clockworkd` |
| T10 | `Gem faraday` — incompatibilidade de versão | Aplicação (Ruby) | Faraday v2.0+ exige módulo de retry separado | `gem install faraday-retry` |
| T11 | `status=203/EXEC` em serviços Systemd | SELinux (MAC) | Rótulo `httpd_sys_content_t` impede transição de processo nos binários Ruby | Alterar contexto para `bin_t`: `chcon -t bin_t <binário>` |
| T12 | `Access denied for user 'root'` no MariaDB | Banco de Dados | Credenciais divergentes entre o pacote e o banco instanciado | Recriar usuário `obs` no MariaDB e atualizar `database.yml` |
| T13 | `Can't open PID file` no Systemd | SELinux (MAC) | Isolamento do domínio `init_t` bloqueia leitura na pasta temporária da aplicação | Mover PID para `/run/obs/` via override do Systemd |
| T14 | `Invalid command 'Passenger...'` no Apache | Web Server | Módulo `.so` presente mas sem diretiva `LoadModule` | Criar `/etc/apache2/conf.d/passenger.conf` com `LoadModule passenger_module` |
| T15 | `PassengerRoot not specified` | Web Server | Diretiva de localização do motor Ruby ausente para o Apache | Adicionar `PassengerRoot /etc/passenger/locations.ini` ao `passenger.conf` |
| T16 | Certificado TLS não lido pelo Apache | SELinux (MAC) | Certificado auto-assinado sem rótulo `cert_t` | `chcon -R -t cert_t /srv/obs/certs/` |
| T17 | `could not bind to address 0.0.0.0:82` | SELinux (MAC) | Porta 82 não mapeada no contexto `http_port_t` | `semanage port -a -t http_port_t -p tcp 82` |
| T18 | Erro HTTP 403 Forbidden | Permissão (DAC) | Apache (`wwwrun`) sem privilégio na árvore base da aplicação | `chown -R wwwrun:www /srv/www/obs/api` |

---

## Comandos de Diagnóstico por Camada

### SELinux

```bash
# Verificar modo atual
sestatus

# Extrair negações recentes (últimas 20)
grep -i denied /var/log/audit/audit.log | tail -20

# Filtrar negações por processo
grep -i denied /var/log/audit/audit.log | grep <processo>

# Gerar módulo de política a partir das negações
grep <processo> /var/log/audit/audit.log | audit2allow -M <nome_modulo>

# Instalar módulo gerado
semodule -i <nome_modulo>.pp

# Verificar módulos instalados
semodule -l | grep obs

# Verificar contexto SELinux de arquivo/diretório
ls -lZ <caminho>

# Testar em modo Permissive (temporário — apenas para diagnóstico)
setenforce 0
# ... teste ...
setenforce 1  # SEMPRE retornar ao modo Enforcing
```

### Systemd / Serviços

```bash
# Listar todas as unidades OBS
systemctl list-unit-files | grep -E '^obs'

# Ver log do journal de um serviço específico
journalctl -xeu <servico>.service

# Ver últimas linhas do log do OBS
tail -n 20 /srv/obs/log/redis.log
tail -n 20 /srv/obs/log/src_server.log
tail -n 20 /srv/obs/log/rep_server.log
tail -n 20 /srv/obs/log/dispatcher.log
```

### MariaDB

```bash
# Verificar usuários e bases de dados
mysql -u root -e "SELECT user, host FROM mysql.user;"
mysql -u root -e "SHOW DATABASES;"

# Verificar grants do usuário obs
mysql -u root -e "SHOW GRANTS FOR 'obs'@'localhost';"
```

### Redis

```bash
# Verificar se o Redis está ouvindo
ss -tlnp | grep 6379

# Testar conexão
redis-cli -u redis://127.0.0.1:6379 ping
# Resposta esperada: PONG

# Verificar configuração carregada
grep "redisserver" /usr/lib/obs/server/BSConfig.pm
grep "redisserver" /usr/lib/obs/server/BSConfig.local.pm
```

### Apache / Frontend

```bash
# Verificar sintaxe do Apache antes de reiniciar
apachectl configtest

# Verificar módulos carregados
apachectl -M | grep -E 'passenger|ssl|proxy|rewrite'

# Log de erro do Apache
tail -f /var/log/apache2/error_log

# Log de produção Rails
tail -f /srv/www/obs/api/log/production.log

# Testar saúde local
curl -I -k https://localhost/
```

### Portas e Rede

```bash
# Verificar bindings ativos
ss -tulpn | grep -E ':(80|443|82|5252|5352|6379|3306)'

# Verificar conectividade com backend (em nó de worker)
nc -zv <IP-BACKEND> 5252
nc -zv <IP-BACKEND> 5352
```

---

## Checklist de Diagnóstico Sequencial (para novas instalações)

Se um serviço não sobe, execute na ordem:

1. `systemctl status <servico>` — identificar código de saída (13=SELinux/perm, 29=aplicação/config)
2. `journalctl -xeu <servico>` — ver log completo do journal
3. `grep <daemon> /var/log/audit/audit.log` — verificar bloqueios SELinux
4. `cat /srv/obs/log/<daemon>.log` — verificar log interno do OBS
5. Identificar camada: Kernel (SELinux) → Permissão (DAC/chown) → Configuração (BSConfig) → Rede (Redis/MariaDB)
6. Aplicar correção na camada identificada
7. `systemctl restart <servico> && systemctl status <servico>`
