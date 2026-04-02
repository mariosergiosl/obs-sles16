# OBS — Open Build Service no SLES 16

Documentação técnica completa de instalação, configuração e operação do **Open Build Service (OBS)** no **SUSE Linux Enterprise Server 16**, registrada a partir de um ambiente de laboratório single-node.

> **Repositório relacionado:** A topologia de produção multi-servidor está documentada em
> [`obs-sles16-multinode`](https://github.com/mariosergiosl/obs-sles16-multinode).
> Tudo que foi validado aqui alimenta aquele repositório.

---

## Por que este repositório existe

A instalação do OBS no SLES 16 não é trivial. O SLES 16 traz mudanças estruturais significativas em relação às versões anteriores — SELinux substituindo AppArmor como MAC padrão, Redis com arquitetura de instâncias via systemd, módulos SLE reestruturados — e a branch `OBS:Server:Unstable` é a única disponível para esta versão do sistema operacional no momento desta documentação, o que significa ausência de políticas SELinux pré-compiladas, mudanças silenciosas em variáveis de configuração e comportamentos que diferem da documentação oficial.

Este repositório documenta **o que realmente aconteceu**: cada erro encontrado, cada iteração de diagnóstico, cada decisão técnica — não apenas o resultado final. O objetivo é que qualquer engenheiro que encontre os mesmos problemas tenha um caminho claro, com contexto suficiente para entender *por que* cada passo existe.

---

## Ambiente de Laboratório

| Atributo | Valor |
|----------|-------|
| Hostname | `sles16BBOBS.lab` |
| OS | SLES 16 x86_64 |
| Topologia | Single-node — Frontend, Backend, Workers, DB e Redis no mesmo host |
| Storage `/srv` | Btrfs, 13 GB disponíveis |
| VM de Serviços | `192.168.56.200` — DNS/DHCP, LDAP (389DS), SMB, FTP, NFS, Firewall |
| Repositório OBS | `OBS:Server:Unstable` — única branch disponível para SLES 16 |
| SELinux | Enforcing — módulo local gerado durante o provisionamento |

> **Produção:** Em [`obs-sles16-multinode`](https://github.com/mariosergiosl/obs-sles16-multinode) cada componente abaixo opera em nó dedicado. As notas de produção em cada seção deste documento descrevem essa separação.

---

## O que você vai encontrar aqui

### Problemas reais documentados

Esta instalação enfrentou e resolveu os seguintes problemas, todos documentados com causa raiz, diagnóstico e resolução:

**Dependências de pacote**
- `ghostscript-fonts-std` não disponível — módulo `sle-module-desktop-applications` não existe no SLES 16 (erro 422 no SCC). Resolução: ativação do SUSE Package Hub. Ver [01 — Repositórios](docs/01-repositorios.md).

**Instalação e serviços**
- `/usr/sbin/obs-api-setup` não existe em instalações via repositório — exclusivo do OBS Appliance. Resolução: provisionamento manual via `mysql` + `rake db:setup`. Ver [03 — MariaDB](docs/03-mariadb.md).
- `obs-server.service` não existe — arquitetura modular com daemons independentes. Ver [04 — Backend](docs/04-backend.md).

**Redis — múltiplas camadas de problema**
- `redis.service` não existe no SLES 16 — pacote usa instâncias `redis@.service`. Ver [05 — Redis](docs/05-redis.md).
- `/etc/redis/default.conf` ausente após instalação — template não copiado automaticamente.
- Variável de configuração renomeada silenciosamente: `$redis_server` → `$redisserver` (sem sublinhado).
- Formato do valor alterado: `IP:porta` → URI `redis://IP:porta`.
- Mensagem de erro `No redis server configured` com status=29 após resolução do SELinux.

**SELinux — processo iterativo completo documentado**
- Quatro iterações de `audit2allow` para liberar as permissões do `bs_redis`: `create` → `read/write` → `open` → `ioctl`. Todas as iterações com comandos, saídas e raciocínio estão em [06 — Política SELinux](docs/06-selinux.md).
- Apache bloqueado por falta de booleans e porta 82 não mapeada em `http_port_t`.
- Certificado TLS sem contexto `cert_t`.
- Binários Ruby com contexto errado (`httpd_sys_content_t` em vez de `bin_t`).

**Apache / Frontend**
- Diretiva `LoadModule passenger_module` ausente — módulo `.so` instalado mas sem declaração.
- `PassengerRoot` não especificado — motor Ruby não localizado pelo Apache.
- HTTP 403 por proprietário incorreto em `/srv/www/obs/api`.
- Porta 82/tcp bloqueada pelo SELinux.

---

## Estrutura do Repositório

```
obs-sles16/
├── README.md                      ← este arquivo
├── docs/
│   ├── 00-pre-requisitos.md
│   ├── 01-repositorios.md
│   ├── 02-instalacao-pacotes.md
│   ├── 03-mariadb.md
│   ├── 04-backend.md
│   ├── 05-redis.md
│   ├── 06-selinux.md
│   ├── 07-frontend.md
│   ├── 08-firewall.md
│   ├── 09-verificacao.md
│   ├── 10-topologias.md
│   ├── 11-matriz-lab-prod.md
│   └── 12-troubleshooting.md
├── configs/
│   ├── BSConfig.local.pm          ← configuração Redis para o backend OBS
│   ├── BSConfig.pm.patch          ← patch fallback se .local.pm for ignorado
│   ├── selinux/
│   │   └── obsredis_final.te      ← política SELinux consolidada
│   ├── redis/
│   │   └── default.conf           ← configuração da instância Redis @default
│   └── apache/
│       ├── passenger.conf         ← declaração do módulo Phusion Passenger
│       └── obs-vhost.conf         ← VirtualHost HTTP + HTTPS
├── diagrams/
│   ├── topology-lab.html          ← topologia single-node (este ambiente)
│   └── topology-multinode.html    ← topologia produção descentralizada
└── scripts/
    ├── apply-selinux-policy.sh    ← compila e instala obsredis_final.te
    └── verify-services.sh         ← checklist de saúde do stack completo
```

---

## Índice da Documentação

| # | Documento | O que cobre |
|---|-----------|-------------|
| [00](docs/00-pre-requisitos.md) | Pré-Requisitos | CPU x86-64-v2, FQDN, storage, registro SCC |
| [01](docs/01-repositorios.md) | Repositórios e Módulos | Package Hub, URL correta do OBS Unstable, erro 422 |
| [02](docs/02-instalacao-pacotes.md) | Instalação de Pacotes | `obs-server`, `obs-worker`, `obs-api`, Redis, MariaDB |
| [03](docs/03-mariadb.md) | Banco de Dados | Provisionamento manual, `rake db:setup`, notas de produção |
| [04](docs/04-backend.md) | Serviços de Backend | Mapa completo de daemons, ordem de inicialização |
| [05](docs/05-redis.md) | Redis | Instalação, instâncias systemd, `BSConfig.local.pm`, URI correta |
| [06](docs/06-selinux.md) | Política SELinux | Processo iterativo completo, módulo consolidado final |
| [07](docs/07-frontend.md) | Frontend Apache + Passenger | VirtualHost, TLS, Memcached, Delayed Jobs |
| [08](docs/08-firewall.md) | Firewall | Portas por serviço, regras para topologia distribuída |
| [09](docs/09-verificacao.md) | Verificação Final | Checklist de saúde, comandos de diagnóstico |
| [10](docs/10-topologias.md) | Topologias | Single-node (lab) e multi-node (produção) |
| [11](docs/11-matriz-lab-prod.md) | Matriz Lab × Produção | Comparativo completo de decisões de configuração |
| [12](docs/12-troubleshooting.md) | Troubleshooting | Todos os incidentes com causa raiz e resolução |
| [13](docs/13-tuning.md) | Tuning | Otimização de MariaDB, Redis, Memcached, Apache, Passenger e OS |

---

## Fluxo de Instalação

A sequência abaixo é a ordem correta de execução. Cada passo tem link para a documentação detalhada, incluindo os erros encontrados e como foram resolvidos.

### 1. Pré-requisitos
Valide hardware, FQDN, storage e registro SCC antes de qualquer instalação.
→ [00 — Pré-Requisitos](docs/00-pre-requisitos.md)

### 2. Repositórios e Módulos SLE

```bash
# Ativar SUSE Package Hub (necessário para ghostscript-fonts-std e redis)
SUSEConnect -p PackageHub/16.0/x86_64

# Adicionar repositório OBS — URL correta para SLES 16
# ATENÇÃO: a URL /SLE_.../ da documentação oficial está errada para SLES 16
zypper ar -f \
  https://download.opensuse.org/repositories/OBS:/Server:/Unstable/16.0/ \
  OBS-Server-Unstable

zypper ref
```

→ [01 — Repositórios](docs/01-repositorios.md) | Erros: erro 422 SCC, URL incorreta

### 3. Instalação de Pacotes

Instale todos os componentes em uma única operação. Isso inclui o servidor OBS, o agente worker, a API Rails e suas dependências — entre elas o Redis e o MariaDB, que são abordados em detalhe nas seções [05](docs/05-redis.md) e [03](docs/03-mariadb.md) respectivamente, mas devem estar presentes desde este passo.

```bash
zypper in obs-server obs-worker obs-api

# Instalar Redis (Package Hub) — necessário antes de iniciar o backend
# Detalhes de configuração em: docs/05-redis.md
zypper in redis

# MariaDB já é puxado como dependência do obs-api
# Detalhes de provisionamento em: docs/03-mariadb.md
systemctl enable --now mariadb
```

→ [02 — Instalação de Pacotes](docs/02-instalacao-pacotes.md) | Erros: `ghostscript-fonts-std` ausente

### 4. Política SELinux

Aplique a política **antes** de tentar iniciar qualquer serviço de backend. Sem ela, `obsredis.service` falha com `status=13` (EACCES) e o processo de diagnóstico é longo.

```bash
bash scripts/apply-selinux-policy.sh
```

O processo de descoberta desta política envolveu quatro iterações com `audit2allow`, evoluindo de `status=13` para `status=29` e finalmente para `active (running)`. Todo o processo está documentado em [06 — Política SELinux](docs/06-selinux.md).

→ [06 — SELinux](docs/06-selinux.md) | Erros: EACCES em fifo_file, iterações create/read/write/open/ioctl

### 5. Banco de Dados (MariaDB)

```bash
# Criar banco e usuário de serviço
mysql -u root -e "
  CREATE DATABASE api_production;
  CREATE USER 'obs'@'localhost' IDENTIFIED BY 'opensuse';
  GRANT ALL PRIVILEGES ON api_production.* TO 'obs'@'localhost';
  FLUSH PRIVILEGES;
"

# Aplicar schema Rails
cd /srv/www/obs/api && RAILS_ENV=production /usr/bin/rake db:setup
```

> **Atenção:** `/usr/sbin/obs-api-setup` não existe em instalações via repositório. O provisionamento acima substitui esse utilitário presente apenas no OBS Appliance.

→ [03 — MariaDB](docs/03-mariadb.md) | Erros: `obs-api-setup` não encontrado, depreciação do binário `mysql`

### 6. Redis

O SLES 16 usa instâncias systemd para o Redis. O arquivo de configuração não é criado automaticamente.

```bash
# Criar configuração da instância default
cp /etc/redis/redis.default.conf.template /etc/redis/default.conf
chown redis:redis /etc/redis/default.conf

# Iniciar instância
systemctl enable --now redis@default.service
```

Em seguida, configure o endpoint do Redis no backend OBS. **Atenção:** a variável mudou de nome e de formato na branch Unstable:

```bash
cat <<EOF > /usr/lib/obs/server/BSConfig.local.pm
package BSConfig;
# Variável: $redisserver (SEM sublinhado — mudança silenciosa no Unstable)
# Formato obrigatório: URI redis:// (não apenas IP:porta)
\$redisserver = 'redis://127.0.0.1:6379';
1;
EOF

chown obsrun:obsrun /usr/lib/obs/server/BSConfig.local.pm
chmod 644 /usr/lib/obs/server/BSConfig.local.pm
```

→ [05 — Redis](docs/05-redis.md) | Erros: `redis.service` inexistente, `default.conf` ausente, `No redis server configured`, `$redis_server` vs `$redisserver`

### 7. Serviços de Backend

```bash
# Preparação de armazenamento
systemctl start obsstoragesetup.service
systemctl start obsapisetup.service

# Ajuste de permissões
chown -R obsrun:obsrun /srv/obs

# Serviços centrais
systemctl enable --now \
  obsredis.service \
  obssrcserver.service \
  obsrepserver.service \
  obsdispatcher.service \
  obspublisher.service \
  obsscheduler.service \
  obsworker.service
```

→ [04 — Backend](docs/04-backend.md) | Erros: `obs-server.service` inexistente, aviso Perl benigno no srcserver

### 8. Frontend — Apache + Passenger

```bash
# Módulos Apache
a2enmod ssl headers rewrite proxy proxy_http passenger

# Módulo Passenger (necessário declarar explicitamente)
cp configs/apache/passenger.conf /etc/apache2/conf.d/passenger.conf

# VirtualHost
mv /etc/apache2/vhosts.d/obs.conf.template /etc/apache2/vhosts.d/obs.conf

# Certificado TLS (lab — auto-assinado)
mkdir -p /srv/obs/certs
openssl req -new -x509 -nodes \
  -out /srv/obs/certs/server.crt \
  -keyout /srv/obs/certs/server.key \
  -days 365 -subj "/CN=sles16BBOBS.lab"

# Contexto SELinux para o certificado
chown root:www /srv/obs/certs/server.*
chmod 640 /srv/obs/certs/server.key
chcon -R -t cert_t /srv/obs/certs/
chmod o+rx /srv /srv/obs

# Memcached (necessário — sem ele a API retorna HTTP 400 silenciosamente)
zypper install -y memcached
systemctl enable --now memcached.service

# Permissões da aplicação Rails
chown -R wwwrun:www /srv/www/obs/api

# Ativar SSL e iniciar Apache
sed -i 's/APACHE_SERVER_FLAGS=""/APACHE_SERVER_FLAGS="SSL"/' /etc/sysconfig/apache2
systemctl enable --now apache2.service

# Delayed Jobs e Clockwork
systemctl enable --now obs-api-support.target
```

→ [07 — Frontend](docs/07-frontend.md) | Erros: `Invalid command Passenger`, `PassengerRoot not specified`, HTTP 403, porta 82 bloqueada, certificado sem `cert_t`

### 9. Firewall

```bash
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload
```

→ [08 — Firewall](docs/08-firewall.md)

### 10. Verificação Final

```bash
bash scripts/verify-services.sh
```

→ [09 — Verificação](docs/09-verificacao.md)

---

## Comandos de Diagnóstico Rápido

```bash
# Listar todas as unidades OBS registradas no sistema
systemctl list-unit-files | grep -E '^obs'

# Status do stack de backend
systemctl status obsredis.service obssrcserver.service \
  obsrepserver.service obsdispatcher.service

# Logs de produção Rails em tempo real
tail -f /srv/www/obs/api/log/production.log

# Auditoria de bloqueios SELinux
grep -i denied /var/log/audit/audit.log | tail -20

# Filtrar bloqueios por processo específico
grep -i denied /var/log/audit/audit.log | grep bs_redis

# Gerar módulo SELinux a partir de negações capturadas
grep <processo> /var/log/audit/audit.log | audit2allow -M <nome_modulo>
semodule -i <nome_modulo>.pp

# Verificar portas em escuta
ss -tulpn | grep -E ':(80|443|82|5252|5352|6379|3306)'

# Contexto SELinux de arquivo ou diretório
ls -lZ /srv/obs/events/redis/

# Saúde da fila de jobs assíncronos
sudo -u wwwrun RAILS_ENV=production bin/rails runner \
  "puts Delayed::Job.count"

# Teste de saúde local do frontend
curl -I -k https://localhost/
```

---

## Arquivos de Configuração Versionados

Todos os arquivos em `configs/` estão prontos para copiar para o servidor. Cada um contém comentários explicando o contexto, as decisões tomadas e as diferenças para produção.

| Arquivo | Destino no servidor | Função |
|---------|---------------------|--------|
| `configs/BSConfig.local.pm` | `/usr/lib/obs/server/BSConfig.local.pm` | Endpoint Redis para o backend OBS |
| `configs/selinux/obsredis_final.te` | compilado via `apply-selinux-policy.sh` | Política SELinux consolidada |
| `configs/redis/default.conf` | `/etc/redis/default.conf` | Instância Redis @default |
| `configs/apache/passenger.conf` | `/etc/apache2/conf.d/passenger.conf` | Declaração do módulo Passenger |
| `configs/apache/obs-vhost.conf` | `/etc/apache2/vhosts.d/obs.conf` | VirtualHost HTTP + HTTPS |

---

## Topologias

Os diagramas visuais de topologia estão disponíveis em:

- [`diagrams/topology-lab.html`](diagrams/topology-lab.html) — Single-node (este ambiente)
- [`diagrams/topology-multinode.html`](diagrams/topology-multinode.html) — Produção descentralizada

Descrição textual e comparativo completo em [10 — Topologias](docs/10-topologias.md) e [11 — Matriz Lab × Produção](docs/11-matriz-lab-prod.md).

---

## Troubleshooting

Todos os incidentes encontrados durante este provisionamento estão catalogados em [12 — Troubleshooting](docs/12-troubleshooting.md), incluindo:

- Tabela com sintoma, camada, causa raiz e resolução
- Comandos de diagnóstico por camada (SELinux, Systemd, MariaDB, Redis, Apache)
- Checklist de diagnóstico sequencial para novas instalações

---

## Repositório de Produção

A topologia multi-servidor derivada deste laboratório está em:
**[`obs-sles16-multinode`](https://github.com/mariosergiosl/obs-sles16-multinode)**

Cada seção deste repositório contém um bloco **"Em produção"** descrevendo em qual nó aquele componente opera, como instalá-lo de forma isolada e para onde os arquivos de configuração devem apontar.

---

## Referências

- [OBS Admin Guide](https://openbuildservice.org/help/manuals/obs-admin-guide/)
- [OBS Installation and Configuration](https://openbuildservice.org/help/manuals/obs-admin-guide/obs-cha-installation-and-configuration.html)
- [SUSE SELinux Documentation](https://documentation.suse.com/sles/15-SP5/html/SLES-all/cha-selinux.html)
- Repositório OBS Unstable SLES 16: `https://download.opensuse.org/repositories/OBS:/Server:/Unstable/16.0/`
