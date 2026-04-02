# 00 — Pré-Requisitos

Validação de hardware, rede e armazenamento antes de iniciar a instalação.

---

## 1. Validação de Microarquitetura (x86-64-v2)

O SLES 16 e os pacotes do OBS exigem suporte às instruções `sse4_2` e `popcnt`.

```bash
awk '/flags/{print; exit}' /proc/cpuinfo | grep -oE 'sse4_2|popcnt'
```

**Saída esperada:**
```
sse4_2
popcnt
```

Se nenhuma das flags aparecer, o hardware não suporta o SLES 16.

---

## 2. Resolução de Nomes (FQDN)

```bash
hostname -f
```

O sistema deve retornar um FQDN completo (ex: `sles16BBOBS.lab`).
O registro DNS direto e reverso deve estar propagado no servidor DNS do laboratório.

> **⚠️ Produção:** O registro DNS deve ser resolvível por todos os nós (Frontend, Workers, DB). Em ambientes com múltiplas zonas, configure corretamente o split-DNS.

---

## 3. Armazenamento

```bash
df -hT /srv
```

**Requisitos mínimos:**

| Ambiente | Espaço em `/srv/obs` | Sistema de Arquivos |
|----------|---------------------|---------------------|
| Lab      | ≥ 10 GB (builds pequenos) | Btrfs aceitável |
| Produção | ≥ 500 GB (recomendado LVM dedicado) | **XFS** |

> **⚠️ Produção:** O diretório `/srv/obs` deve residir em um volume lógico (LVM) dedicado ou em armazenamento de rede (SAN/NAS) com alta capacidade de IOPS. O sistema de arquivos **XFS** é recomendado sobre Btrfs para os dados do MariaDB do OBS (evita fragmentação excessiva em cargas pesadas de build).

---

## 4. Registro no SUSE Customer Center (SCC)

Confirme que o sistema está registrado:

```bash
SUSEConnect --status
```

Verifique as extensões disponíveis:

```bash
SUSEConnect --list-extensions
```

O **SUSE Package Hub** deve estar disponível (necessário para dependências do OBS).
Ative-o antes de prosseguir:

```bash
SUSEConnect -p PackageHub/16.0/x86_64
```

---

## 5. Conectividade de Rede

| Destino | Finalidade |
|---------|-----------|
| `download.opensuse.org` | Repositório do OBS |
| `scc.suse.com` | Registro de módulos SLE |
| `192.168.56.200` (lab) | DNS, LDAP, NFS |

---

## Checklist de Pré-Requisitos

- [ ] `sse4_2` e `popcnt` presentes em `/proc/cpuinfo`
- [ ] `hostname -f` retorna FQDN válido
- [ ] DNS direto e reverso propagado
- [ ] Espaço suficiente em `/srv`
- [ ] Sistema registrado no SCC
- [ ] SUSE Package Hub ativado
- [ ] Conectividade com `download.opensuse.org`
