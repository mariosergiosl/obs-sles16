# OBS Open Build Service — SLES 16

Documentação técnica de instalação, configuração e operação do **Open Build Service (OBS)** no **SUSE Linux Enterprise Server 16 (SLES 16)**.

> **Contexto:** Registro de laboratório com anotações de produção embutidas.
> Ambiente de lab: single-node. Referências de produção: topologia descentralizada com workers remotos.

---

## Ambiente de Laboratório

| Atributo         | Valor                          |
|------------------|-------------------------------|
| Hostname         | `sles16BBOBS.lab`              |
| OS               | SLES 16 (x86_64)               |
| Arquitetura      | Single-node (tudo no mesmo host) |
| Storage `/srv`   | Btrfs, 13 GB disponíveis       |
| VM de Serviços   | `192.168.56.200` (DNS, DHCP, LDAP/389DS, SMB, FTP, NFS, Firewall) |
| Módulo OBS       | `OBS:Server:Unstable` (branch de desenvolvimento para SLES 16) |

---

## Índice

| # | Documento | Descrição |
|---|-----------|-----------|
| 00 | [Pré-Requisitos](docs/00-pre-requisitos.md) | Validação de hardware, storage e rede |
| 01 | [Repositórios e Módulos](docs/01-repositorios.md) | Ativação do Package Hub e repositório OBS |
| 02 | [Instalação de Pacotes](docs/02-instalacao-pacotes.md) | `obs-server`, `obs-worker`, `obs-api` |
| 03 | [Banco de Dados (MariaDB)](docs/03-mariadb.md) | Provisionamento da base `api_production` |
| 04 | [Serviços de Backend](docs/04-backend.md) | Mapeamento dos daemons e ordem de inicialização |
| 05 | [Redis](docs/05-redis.md) | Instalação, configuração e integração com OBS |
| 06 | [Política SELinux](docs/06-selinux.md) | Módulo local para `obsredis` em SLES 16 |
| 07 | [Frontend — Apache + Passenger](docs/07-frontend.md) | VirtualHost, TLS, SELinux e Memcached |
| 08 | [Firewall](docs/08-firewall.md) | Abertura de portas via `firewall-cmd` |
| 09 | [Verificação Final](docs/09-verificacao.md) | Checklist de saúde dos serviços |
| 10 | [Topologias](docs/10-topologias.md) | Lab (single-node) e Produção (descentralizada) |
| 11 | [Matriz Lab × Produção](docs/11-matriz-lab-prod.md) | Comparativo e pontos de atenção |
| 12 | [Troubleshooting](docs/12-troubleshooting.md) | Incidentes conhecidos e vetores de resolução |

---

## Arquivos de Configuração Versionados

```
configs/
├── BSConfig.local.pm          # Configuração local do backend OBS (Redis)
├── BSConfig.pm.patch          # Patch cirúrgico aplicado ao BSConfig.pm (fallback)
├── selinux/
│   └── obsredis_final.te      # Política SELinux consolidada para obsredis
├── redis/
│   └── default.conf           # Configuração do Redis (instância @default)
└── apache/
    ├── passenger.conf         # Declaração do módulo Phusion Passenger
    └── obs-vhost.conf         # VirtualHost do OBS (HTTP + HTTPS)
```

---

## Comandos de Diagnóstico Rápido

```bash
# Listar todas as unidades OBS registradas
systemctl list-unit-files | grep -E '^obs'

# Status do stack completo de backend
systemctl status obsredis.service obssrcserver.service obsrepserver.service obsdispatcher.service

# Monitorar log de produção em tempo real
tail -f /srv/www/obs/api/log/production.log

# Auditoria de bloqueios SELinux
grep -i denied /var/log/audit/audit.log

# Verificar bindings de portas HTTP/HTTPS
ss -tulpn | grep -E ':(80|443|82)'

# Saúde da fila de jobs assíncronos
sudo -u wwwrun RAILS_ENV=production bin/rails runner "puts Delayed::Job.count"

# Teste de saúde local do frontend
curl -I -k https://localhost/
```

---

## Referências

- [OBS Admin Guide](https://openbuildservice.org/help/manuals/obs-admin-guide/)
- [OBS Installation and Configuration](https://openbuildservice.org/help/manuals/obs-admin-guide/obs-cha-installation-and-configuration.html)
- [SUSE SELinux Documentation](https://documentation.suse.com/sles/15-SP5/html/SLES-all/cha-selinux.html)
- Repositório OBS Unstable para SLES 16: `https://download.opensuse.org/repositories/OBS:/Server:/Unstable/16.0/`
