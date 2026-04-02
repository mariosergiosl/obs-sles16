# 06 — Política SELinux

O SLES 16 consolidou o **SELinux** como módulo de segurança (MAC) primário (substituindo o AppArmor das versões anteriores). O pacote OBS da branch Unstable não inclui políticas SELinux pré-compiladas para SLES 16, exigindo geração de módulo local.

> **Princípio:** O SELinux **não deve ser desativado**. A política deve ser ajustada para permitir a operação da aplicação mantendo o MAC ativo.

---

## Contexto do Problema

O serviço `obsredis.service` opera sob o domínio genérico `init_t` e precisa criar e manipular um arquivo FIFO (`named pipe`) em `/srv/obs/events/redis/.ping`, que possui o contexto `var_t`.

A política `targeted` padrão bloqueia esta operação, pois não existe uma política nativa do OBS para SLES 16.

**Log de auditoria relevante:**
```
avc: denied { create } for comm="bs_redis" name=".ping"
    scontext=system_u:system_r:init_t:s0
    tcontext=system_u:object_r:var_t:s0 tclass=fifo_file
```

---

## Aplicar a Política Consolidada (Uma Única Vez)

> Esta política consolida todas as permissões necessárias identificadas durante o processo de troubleshooting. Em novas instalações, basta executar os comandos abaixo — sem processo iterativo.

### Passo 1 — Criar o arquivo de política

```bash
cat <<'EOF' > /tmp/obsredis_final.te
module obsredis_final 1.0;

require {
    type init_t;
    type var_t;
    class fifo_file { create read write open ioctl };
    class dir { add_name write search };
}

# Permite que o bs_redis (init_t) crie e manipule o FIFO .ping
# no diretório de eventos do OBS (var_t)
allow init_t var_t:fifo_file { create read write open ioctl };
allow init_t var_t:dir { add_name write search };
EOF
```

Veja o arquivo versionado em [`configs/selinux/obsredis_final.te`](../configs/selinux/obsredis_final.te).

### Passo 2 — Compilar o módulo

```bash
checkmodule -M -m -o /tmp/obsredis_final.mod /tmp/obsredis_final.te
semodule_package -o /tmp/obsredis_final.pp -m /tmp/obsredis_final.mod
```

### Passo 3 — Instalar o módulo no kernel

```bash
semodule -i /tmp/obsredis_final.pp
```

### Passo 4 — Verificar a instalação

```bash
semodule -l | grep obsredis
```

---

## Permissões SELinux para o Apache/Frontend

Configure as variáveis booleanas do SELinux para permitir que o Apache atue como proxy reverso:

```bash
setsebool -P httpd_can_network_connect 1
setsebool -P httpd_can_network_relay 1
setsebool -P httpd_execmem 1
```

Mapeie a porta `82/tcp` (usada internamente pelo OBS) ao contexto `http_port_t`:

```bash
semanage port -a -t http_port_t -p tcp 82
```

---

## Diagnóstico de Novos Bloqueios (se necessário)

Se surgir um novo bloqueio SELinux em versões futuras do pacote:

```bash
# Verificar status do SELinux
sestatus

# Extrair negações do log de auditoria (filtradas por processo)
grep -i denied /var/log/audit/audit.log | grep <nome_do_processo> | tail -20

# Gerar módulo temporário de diagnóstico
grep <nome_do_processo> /var/log/audit/audit.log | audit2allow -M <nome_modulo>

# Instalar o módulo temporário
semodule -i <nome_modulo>.pp
```

---

## Histórico do Processo de Troubleshooting (Referência)

Esta tabela documenta as iterações realizadas durante o lab para identificar as permissões necessárias:

| Iteração | Permissão Adicionada | Código Anterior | Resultado |
|----------|---------------------|-----------------|-----------|
| v1 | `fifo_file { create }` | 13 (EACCES) | Arquivo `.ping` criado |
| v2 | `fifo_file { read write }` | 13 (EACCES) | Falha em `open` |
| v3 | `fifo_file { open }` | 13 (EACCES) | Falha em `ioctl` |
| v4 | `fifo_file { ioctl }` | 13 → **29** | SELinux resolvido; erro passa para camada de aplicação |
| final | `dir { add_name write search }` | — | Política consolidada completa |

> **Nota técnica:** A transição do código 13 (`EACCES`) para 29 na iteração v4 confirmou que o SELinux havia sido superado e o problema restante era de configuração de aplicação (`No redis server configured`). O processo iterativo com `audit2allow` é o método padrão de engenharia para homologar aplicações em sistemas operacionais novos sem política SELinux pré-definida.

> **Contexto de produção:** Em ambientes de produção, o ideal é que os binários do OBS possuam domínios próprios (ex: `obs_server_t`). A ausência dessa política no SLES 16 é uma limitação da branch Unstable e deve ser reportada aos mantenedores do pacote.

---

## Notas para Ambiente de Produção

> O arquivo `obsredis_final.pp` compilado deve ser armazenado no repositório e distribuído via automação (Salt/Ansible) para todos os nós do cluster OBS. Aplique-o **antes** de iniciar os serviços de backend em cada nó.
