# 10 — Topologias

Descrição das topologias de implantação do Open Build Service: laboratório (single-node) e produção (descentralizada).

> Os diagramas visuais estão disponíveis no arquivo `docs/topologias-visual.html` gerado pelo processo de documentação.

---

## Topologia 1 — Laboratório (Single-Node)

**Todos os componentes no mesmo host.**

```
┌─────────────────────────────────────────────────────────────┐
│ sles16BBOBS.lab (192.168.56.x)                              │
│                                                             │
│  ┌─────────────────┐   ┌─────────────────────────────────┐ │
│  │   FRONTEND      │   │         BACKEND                 │ │
│  │                 │   │                                 │ │
│  │  Apache HTTPD   │   │  obssrcserver  (porta 5252)     │ │
│  │  + Passenger    │   │  obsrepserver  (porta 5352)     │ │
│  │  (HTTP:80)      │   │  obsdispatcher                  │ │
│  │  (HTTPS:443)    │   │  obspublisher                   │ │
│  │                 │   │  obsscheduler                   │ │
│  │  OBS Rails API  │   │  obsredis  ──────► Redis        │ │
│  │  Delayed Jobs   │   │                   (@default)    │ │
│  │  Clockwork      │   │  obsworker (build local)        │ │
│  └────────┬────────┘   └─────────────────────────────────┘ │
│           │                                                 │
│  ┌────────▼────────┐   ┌─────────────────────────────────┐ │
│  │   MariaDB       │   │  Memcached                      │ │
│  │  api_production │   │  (sessões Rails)                │ │
│  └─────────────────┘   └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
         │
         │ Rede Interna (192.168.56.0/24)
         │
┌────────▼────────────────────┐
│ VM de Serviços (192.168.56.200) │
│  DNS/DHCP  │  LDAP (389DS)  │
│  SMB/FTP   │  NFS           │
│  Firewall  │  hostPM        │
└─────────────────────────────┘
```

**Características do Lab:**
- Todos os serviços no mesmo host (sles16BBOBS)
- Storage Btrfs em `/srv` (13 GB — suficiente para builds de validação)
- LDAP externo em `192.168.56.200` (configuração na fase 2)
- Certificado TLS auto-assinado

---

## Topologia 2 — Produção (Descentralizada)

**Separação física/lógica dos componentes para alta disponibilidade e performance.**

### Arquitetura de Referência

```
                          ┌──────────────────┐
                          │  Load Balancer   │
                          │  (HAProxy/NGINX) │
                          │  80/443          │
                          └────────┬─────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
   ┌──────────▼────────┐ ┌─────────▼───────┐ ┌─────────▼────────┐
   │  Frontend Node 1  │ │ Frontend Node 2 │ │  Frontend Node N │
   │                   │ │                 │ │                  │
   │  Apache+Passenger │ │ Apache+Passenger│ │ Apache+Passenger │
   │  OBS Rails API    │ │ OBS Rails API   │ │ OBS Rails API    │
   │  Delayed Jobs     │ │ Delayed Jobs    │ │ Delayed Jobs     │
   │  Memcached*       │ │ Memcached*      │ │ Memcached*       │
   └──────────┬────────┘ └─────────┬───────┘ └─────────┬────────┘
              │                    │                    │
              └──────────────┬─────┘────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
   ┌──────────▼──────────┐   ┌─────────────▼────────────┐
   │   Backend Node      │   │   Database Node (HA)     │
   │                     │   │                          │
   │  obssrcserver :5252 │   │  MariaDB / Galera Cluster│
   │  obsrepserver :5352 │   │  (ativo-ativo)            │
   │  obsdispatcher      │   │  innodb_buffer_pool ~70%  │
   │  obspublisher       │   │  RAM                     │
   │  obsscheduler       │   └──────────────────────────┘
   │  obsredis ─────────────────────────────┐
   └─────────────────────┘                 │
                                           │
                              ┌────────────▼────────────┐
                              │   Redis Node            │
                              │   (redis@default)       │
                              │   Persistência AOF      │
                              │   Porta 6379            │
                              └─────────────────────────┘
              │
              │  Rede Interna de Workers (isolada)
              │
   ┌──────────▼────────────────────────────────────────────────┐
   │                   Worker Pool                             │
   │                                                           │
   │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │
   │  │ Worker 01   │  │ Worker 02   │  │ Worker NN   │      │
   │  │ obsworker   │  │ obsworker   │  │ obsworker   │      │
   │  │ x86_64      │  │ x86_64      │  │ aarch64     │      │
   │  │ /var/cache  │  │ /var/cache  │  │ /var/cache  │      │
   │  │ /obs/worker │  │ /obs/worker │  │ /obs/worker │      │
   │  └─────────────┘  └─────────────┘  └─────────────┘      │
   └───────────────────────────────────────────────────────────┘

* Memcached: preferível cluster dedicado compartilhado entre todos os frontends
```

---

## Componentes Distribuíveis — Tabela de Referência

| Componente | Lab | Produção | Nó Recomendado em Produção |
|-----------|-----|----------|----------------------------|
| Apache + Passenger | ✅ single-node | ✅ N frontends | Frontend Node(s) |
| OBS Rails API | ✅ single-node | ✅ N instâncias | Frontend Node(s) |
| Delayed Jobs / Clockwork | ✅ single-node | ✅ por frontend | Frontend Node(s) |
| Memcached | ✅ single-node | ✅ cluster dedicado | Memcached Node(s) |
| obssrcserver | ✅ single-node | ✅ separado | Backend Node |
| obsrepserver | ✅ single-node | ✅ separado | Backend Node |
| obsdispatcher | ✅ single-node | ✅ separado | Backend Node |
| obspublisher | ✅ single-node | ✅ separado | Backend Node |
| obsworker | ✅ single-node | ✅ pool dedicado | Worker Node(s) |
| Redis | ✅ loopback | ✅ servidor dedicado | Redis Node |
| MariaDB | ✅ single-node | ✅ Galera Cluster | Database Node(s) |

---

## Configuração do Worker Remoto (Topologia Descentralizada)

Em cada nó worker, instale apenas `obs-worker` e configure o endpoint do servidor backend:

```bash
# Instalar apenas o agente worker
zypper in obs-worker

# Configurar o endereço do servidor de backend
cat <<EOF >> /usr/lib/obs/server/BSConfig.local.pm
package BSConfig;
# Endereço do Backend Node
our $srcserver = 'http://<IP-BACKEND>:5252';
our $reposerver = 'http://<IP-BACKEND>:5352';
1;
EOF

# Habilitar o worker
systemctl enable --now obsworker.service
```

> **Firewall nos workers:** Os nós worker precisam alcançar o backend nas portas `5252/tcp` e `5352/tcp`, e o repositório de pacotes do OBS (download de dependências de build).
