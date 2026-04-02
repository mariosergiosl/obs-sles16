# 01 — Repositórios e Módulos

Configuração dos repositórios necessários para instalação do OBS no SLES 16.

---

## 1. Ativação do SUSE Package Hub

O pacote `ghostscript-fonts-std` (dependência do `obs-api`) é fornecido pelo **SUSE Package Hub**.
O módulo `sle-module-desktop-applications` **não existe** na estrutura de produtos do SLES 16 — tentativas de ativação retornam erro 422.

```bash
SUSEConnect -p PackageHub/16.0/x86_64
```

**Saída esperada:**
```
Registering system to SUSE Customer Center
Activating PackageHub 16.0 x86_64 ...
-> Adding service to system ...
-> Installing release package ...
Successfully registered system
```

Após a ativação, sincronize o cache de metadados:

```bash
zypper ref
```

> **⚠️ Produção:** Em ambientes sem acesso direto ao SCC, provisione um servidor **RMT (Repository Mirroring Tool)** interno contendo a base completa de módulos SLE ativada. Isso garante integridade da árvore de dependências e operação offline.

---

## 2. Repositório OBS Server (Unstable)

> **Nota:** A URL inicial sugerida pela documentação oficial (`/SLE_...`) é incorreta para SLES 16. A URL correta usa o path `/16.0/`.

Adicione o repositório oficial do OBS para SLES 16:

```bash
zypper ar -f \
  https://download.opensuse.org/repositories/OBS:/Server:/Unstable/16.0/ \
  OBS-Server-Unstable
```

Sincronize novamente os metadados (inclui o novo repositório):

```bash
zypper ref
```

Confirme que o repositório foi adicionado corretamente:

```bash
zypper lr -d OBS-Server-Unstable
```

---

## Resumo dos Repositórios Ativos

| Repositório | Finalidade |
|-------------|-----------|
| `SUSE_Linux_Enterprise_Server_16.0_x86_64` | Base do sistema operacional |
| `SUSE_Package_Hub_16.0_x86_64` | Pacotes complementares (ghostscript, redis, etc.) |
| `OBS-Server-Unstable` | Pacotes do Open Build Service para SLES 16 |

> **⚠️ Produção (branch):** A branch `:Unstable` é a única disponível para SLES 16 no momento desta documentação. Em ambientes produtivos, monitore a disponibilização de uma branch `:Stable` ou `:Maintenance` e planeje a migração. As políticas de segurança (SELinux) foram geradas com base nesta branch; uma atualização de pacote pode exigir revisão do módulo SELinux.
