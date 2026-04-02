# 11 — Matriz Lab × Produção

Comparativo de decisões de configuração entre o ambiente de laboratório e o ambiente de produção.

---

## Matriz de Diferenças

| Categoria | Laboratório | Produção | Impacto se Ignorado |
|-----------|-------------|----------|---------------------|
| **Topologia** | Single-node (tudo no mesmo host) | Descentralizada (nós dedicados por função) | Picos de build degradam WebUI e API |
| **Storage** | Btrfs, 13 GB em `/srv` (compartilhado) | LVM dedicado, XFS, ≥ 500 GB para `/srv/obs` | Espaço esgotado nos primeiros builds; fragmentação |
| **MariaDB — Host** | Mesmo host do frontend | Servidor ou cluster dedicado (Galera) | Contenda de CPU/RAM entre builds e consultas DB |
| **MariaDB — Buffer Pool** | Default | `innodb_buffer_pool_size = 60-70% RAM` em `/etc/my.cnf` | Gargalos de I/O na API durante carga alta |
| **MariaDB — Segurança** | Senha padrão (`opensuse`) | `mysql_secure_installation` + senha forte | Acesso não autorizado ao banco |
| **Redis — Host** | `127.0.0.1` (loopback) | Servidor dedicado (IP interno) | Contenção de RAM/CPU com builds e DB |
| **Redis — Persistência** | Sem configuração (memória volátil) | `appendonly yes` em `default.conf` | Perda de filas de jobs em reinicialização |
| **Redis — Autenticação** | Sem senha | `requirepass <senha>` + URI `redis://:<senha>@...` | Acesso não autorizado às filas |
| **Repositório OBS** | `:Unstable` (único disponível para SLES 16) | Monitorar `:Stable` ou `:Maintenance` quando disponível | Pacotes sem suporte oficial em produção |
| **Módulo SLE** | SUSE Package Hub (via SCC direto) | RMT interno com módulos espelhados | Indisponibilidade em ambientes air-gapped |
| **Certificado TLS** | Auto-assinado (openssl req) | CA interna ou pública; TLS 1.2+ apenas | Avisos de segurança; vulnerabilidade MITM |
| **SELinux** | Módulo local `obsredis_final.pp` gerado iterativamente | Mesmo módulo aplicado via automação (Salt/Ansible) antes de iniciar serviços | Serviços falham com status=13 (EACCES) |
| **BSConfig** | Patch direto em `BSConfig.pm` (fallback) | `BSConfig.local.pm` persistente | Configuração perdida em atualização de pacote |
| **Workers** | Local no mesmo host | Nós remotos dedicados (pool) | Build consome CPU/RAM do frontend |
| **Workers — Arquiteturas** | x86_64 (local) | x86_64 + aarch64 + outros (nós cruzados) | Impossibilidade de compilar para múltiplas arquiteturas |
| **Firewall — Redis** | Apenas loopback | Regra por origem: apenas nós OBS acessam 6379 | Exposição do broker de mensagens à rede |
| **Firewall — MariaDB** | Apenas loopback | Regra por origem: apenas nós OBS acessam 3306 | Exposição do banco de dados à rede |
| **Memcached** | Local (loopback) | Cluster dedicado compartilhado entre frontends | Sessões inconsistentes entre frontends (logouts) |
| **LDAP** | Configurado na fase 2 (pós-validação) | Configurado antes da entrada em produção | Sem autenticação centralizada |
| **Monitoramento** | Manual (tail/grep) | Agente de monitoramento (Prometheus/Zabbix) + alertas | Incidentes não detectados automaticamente |
| **Backup** | Não coberto no lab | Backup de `/srv/obs`, dump de `api_production`, snapshot Redis | Perda de dados em falha de disco |
| **Log Centralizado** | `/srv/obs/log/` local | Centralizado (Loki/Elasticsearch/Splunk) | Logs perdidos em falha do nó |

---

## Pontos de Mudança de Configuração por Fase

### Durante a Instalação

| Arquivo | Lab | Produção |
|---------|-----|----------|
| `BSConfig.local.pm` | `$redisserver = 'redis://127.0.0.1:6379'` | `$redisserver = 'redis://<IP-REDIS>:6379'` |
| `BSConfig.local.pm` | — | `$srcserver = 'http://<IP-BACKEND>:5252'` |
| `BSConfig.local.pm` | — | `$reposerver = 'http://<IP-BACKEND>:5352'` |
| `/etc/my.cnf` | Default | `innodb_buffer_pool_size` configurado |
| `/etc/redis/default.conf` | Template padrão | `appendonly yes`, `requirepass <senha>` |
| `/etc/apache2/vhosts.d/obs.conf` | Certificado auto-assinado | Certificado de CA válido |

### Após a Instalação

| Ação | Lab | Produção |
|------|-----|----------|
| Módulo LDAP | Fase 2 (opcional no lab) | Obrigatório antes de go-live |
| mysql_secure_installation | Não executado | Obrigatório |
| Monitoramento de I/O em `/srv/obs` | Manual | Automatizado |
| Política de backup | Não definida | Definida e testada |

---

## Serviços que Mudam de Host em Produção

```
LAB (single-node)          PRODUÇÃO (descentralizada)
─────────────────          ──────────────────────────
sles16BBOBS                frontend-01, frontend-02, ...
  ├── Apache               ├── Apache + Passenger
  ├── Rails API            └── Rails API
  ├── Delayed Jobs
  ├── Memcached            memcached-01, memcached-02
  │
  ├── obssrcserver         backend-01
  ├── obsrepserver         ├── obssrcserver :5252
  ├── obsdispatcher        ├── obsrepserver :5352
  ├── obspublisher         ├── obsdispatcher
  │                        └── obspublisher
  │
  ├── obsworker            worker-01, worker-02, worker-N
  │                        └── obsworker (por arquitetura)
  │
  ├── redis@default        redis-01
  │                        └── redis@default (AOF habilitado)
  │
  └── mariadb              db-01, db-02 (Galera)
                           └── MariaDB Galera Cluster
```
