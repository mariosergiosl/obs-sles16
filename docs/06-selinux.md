# 06 — Política SELinux

O SLES 16 consolidou o **SELinux** como módulo de segurança (MAC) primário, substituindo o AppArmor das versões anteriores. O pacote OBS da branch `Unstable` não inclui políticas SELinux pré-compiladas para SLES 16, exigindo geração de módulos locais.

Durante o provisionamento deste laboratório foram identificados e resolvidos **dois grupos independentes de bloqueios SELinux**: um relacionado ao daemon `obsredis` (backend) e outro ao Apache HTTPD com o frontend Rails.

> **Princípio:** O SELinux **não deve ser desativado**. A política deve ser ajustada para permitir a operação da aplicação mantendo o MAC ativo. A tentativa de desativar o SELinux foi avaliada e descartada — a abordagem correta é sempre ajustar a política.

---

## Arquivos de Política

| Arquivo | Serviço | Cobre |
|---------|---------|-------|
| [`configs/selinux/obsredis.te`](../configs/selinux/obsredis.te) | `obsredis.service` / `bs_redis` | Acesso ao FIFO `.ping` em `/srv/obs/events/redis/` |
| [`configs/selinux/obs-apache.te`](../configs/selinux/obs-apache.te) | `apache2.service` / Passenger | Execução de binários Ruby pelo Apache |

> Os bloqueios de **porta 82**, **booleans** e **certificado TLS** são resolvidos via `semanage`, `setsebool` e `chcon` — não requerem módulo de política e estão documentados na seção [Grupo 2](#grupo-2--selinux-do-apache--frontend) abaixo.

---

## Aplicação — Script Automatizado (Recomendado)

O script [`scripts/apply-selinux-policy.sh`](../scripts/apply-selinux-policy.sh) compila e instala **ambas** as políticas, configura os booleans e mapeia a porta 82 em uma única execução:

```bash
bash scripts/apply-selinux-policy.sh
```

Execute este script **antes** de tentar iniciar qualquer serviço de backend ou frontend. Sem as políticas aplicadas, os serviços falham imediatamente com `status=13` (EACCES).

---

## Grupo 1 — SELinux do obsredis (Backend)

### Contexto do Problema

O serviço `obsredis.service` opera sob o domínio genérico `init_t` e precisa criar e manipular um arquivo FIFO (`named pipe`) em `/srv/obs/events/redis/.ping`, cujo contexto é `var_t`. A política `targeted` padrão bloqueia esta operação porque não existe uma política nativa do OBS para SLES 16.

**Verificação do contexto do diretório:**
```bash
ls -lZ /srv/obs/events/redis/
# drwxr-xr-x. 1 obsrun obsrun system_u:object_r:var_t:s0
```

O sufixo `.` na string de permissão (`drwxr-xr-x.`) indica presença de contexto de segurança estendido — confirmação de que o bloqueio é SELinux, não permissão DAC.

### Aplicação da Política obsredis

```bash
checkmodule -M -m \
    -o /tmp/obsredis.mod \
    configs/selinux/obsredis.te

semodule_package \
    -o /tmp/obsredis.pp \
    -m /tmp/obsredis.mod

semodule -i /tmp/obsredis.pp

# Verificar instalação
semodule -l | grep obsredis
```

### Histórico do Processo — obsredis

O processo de descoberta foi iterativo. O SELinux bloqueia **uma chamada de sistema por vez** — ao liberar uma, o processo avança para a próxima operação e é bloqueado novamente. Cada iteração seguiu o mesmo padrão:

```bash
# 1. Extrair as negações do log de auditoria para o processo
grep "bs_redis" /var/log/audit/audit.log | tail -n 10

# 2. Gerar módulo com todas as negações capturadas até o momento
grep "bs_redis" /var/log/audit/audit.log | audit2allow -M obsredis_vN

# 3. Instalar o módulo gerado
semodule -i obsredis_vN.pp

# 4. Reiniciar o serviço e observar o novo comportamento
systemctl restart obsredis.service
systemctl status obsredis.service
```

**Progressão das iterações:**

| Iteração | Permissão liberada | Exit code antes | Exit code depois | Resultado observado |
|----------|--------------------|----------------|-----------------|---------------------|
| v1 | `fifo_file { create }` | 13 | 13 | Arquivo `.ping` criado com sucesso |
| v2 | `fifo_file { read write }` | 13 | 13 | Falhou em `open` |
| v3 | `fifo_file { open }` | 13 | 13 | Falhou em `ioctl` |
| v4 | `fifo_file { ioctl }` + `dir { add_name write search }` | 13 | **29** | SELinux superado — erro migrou para camada de aplicação |
| final | Consolidação de v1-v4 em `obsredis.te` | — | **active (running)** | Política única para novas instalações |

**Extrato completo dos logs de auditoria (sequência real):**

```
# v1 — create bloqueado
avc: denied { create } for pid=11338 comm="bs_redis" name=".ping"
    scontext=system_u:system_r:init_t:s0
    tcontext=system_u:object_r:var_t:s0 tclass=fifo_file permissive=0

# v2 — read/write bloqueado
avc: denied { read write } for pid=12859 comm="bs_redis" name=".ping"
    dev="sda2" ino=4050
    scontext=system_u:system_r:init_t:s0
    tcontext=system_u:object_r:var_t:s0 tclass=fifo_file permissive=0

# v3 — open bloqueado
avc: denied { open } for pid=12902 comm="bs_redis"
    path="/srv/obs/events/redis/.ping" dev="sda2" ino=4050
    scontext=system_u:system_r:init_t:s0
    tcontext=system_u:object_r:var_t:s0 tclass=fifo_file permissive=0

# v4 — ioctl bloqueado
avc: denied { ioctl } for pid=12935 comm="bs_redis"
    path="/srv/obs/events/redis/.ping" dev="sda2" ino=4050
    ioctlcmd=0x5401
    scontext=system_u:system_r:init_t:s0
    tcontext=system_u:object_r:var_t:s0 tclass=fifo_file permissive=0
```

> **Nota técnica:** O `ioctlcmd=0x5401` corresponde ao `TCGETS` — operação de controle de I/O em pipes/terminais. O SELinux trata `read/write`, `open` e `ioctl` como permissões separadas para arquivos FIFO, o que explica por que cada iteração liberou apenas uma camada de acesso.

**Diagnóstico decisivo — modo Permissive:**

Para confirmar que o SELinux era o único bloqueio na transição de `status=13` para `status=29`, foi executado:

```bash
setenforce 0
systemctl restart obsredis.service
systemctl status obsredis.service
# → continuou falhando com status=29
setenforce 1
```

A persistência do `status=29` com SELinux em Permissive confirmou que o SELinux havia sido superado e o problema restante era de configuração de aplicação — a variável `$redisserver` ausente no `BSConfig.pm`. Ver [05 — Redis](05-redis.md).

---

## Grupo 2 — SELinux do Apache / Frontend

O frontend OBS (Apache + Passenger + Rails) apresentou **quatro bloqueios SELinux independentes**, identificados em diferentes momentos do provisionamento. Dois são resolvidos via módulo de política (`obs-apache.te`) e dois via comandos diretos (`semanage` e `chcon`).

### 2.1 — Binários Ruby com contexto incorreto (`status=203/EXEC`)

**Sintoma:** Serviços como `obs-clockwork` e `obs-delayedjob-*` falham com `status=203/EXEC`.

**Causa:** Os binários Ruby da aplicação possuem contexto `httpd_sys_content_t`, que não permite transição de processo pelo Apache (`httpd_t`).

**Diagnóstico:**
```bash
grep -i denied /var/log/audit/audit.log | grep -E "clockwork|delayed"
# avc: denied { execute } for comm="httpd" name="clockworkd"
#     scontext=system_u:system_r:httpd_t:s0
#     tcontext=system_u:object_r:httpd_sys_content_t:s0 tclass=file

ls -lZ /srv/www/obs/api/bin/clockworkd
# system_u:object_r:httpd_sys_content_t:s0
```

**Resolução via `chcon`:**
```bash
chcon -t bin_t /srv/www/obs/api/bin/clockworkd
chcon -t bin_t /srv/www/obs/api/bin/delayed_job

# Verificar
ls -lZ /srv/www/obs/api/bin/clockworkd
# system_u:object_r:bin_t:s0
```

Este bloqueio também é coberto pelo módulo `obs-apache.te` com a regra `allow httpd_t httpd_sys_content_t:file { execute execute_no_trans }`.

### 2.2 — Certificado TLS sem contexto `cert_t`

**Sintoma:** Apache falha ao ler o certificado TLS — erro nos logs ou no `audit.log`.

**Causa:** O certificado gerado com `openssl req` herda o contexto do diretório pai (`var_t`). O Apache (`httpd_t`) só pode ler arquivos de certificado com contexto `cert_t`.

**Diagnóstico:**
```bash
grep -i denied /var/log/audit/audit.log | grep "server.crt\|server.key"
# avc: denied { read } for comm="httpd" name="server.crt"
#     scontext=system_u:system_r:httpd_t:s0
#     tcontext=system_u:object_r:var_t:s0 tclass=file

ls -lZ /srv/obs/certs/
# system_u:object_r:var_t:s0 server.crt
# system_u:object_r:var_t:s0 server.key
```

**Resolução:**
```bash
chcon -R -t cert_t /srv/obs/certs/

# Verificar
ls -lZ /srv/obs/certs/
# system_u:object_r:cert_t:s0 server.crt
# system_u:object_r:cert_t:s0 server.key
```

> Não requer módulo de política — `cert_t` já é reconhecido pela política `targeted` padrão para leitura pelo `httpd_t`.

### 2.3 — Porta 82/tcp não mapeada em `http_port_t`

**Sintoma:** Apache falha ao iniciar com `could not bind to address 0.0.0.0:82`.

**Causa:** O OBS usa `82/tcp` internamente. A política padrão do `httpd_t` só permite bind em portas mapeadas como `http_port_t`. A porta 82 não está incluída por padrão.

**Diagnóstico:**
```bash
grep -i denied /var/log/audit/audit.log | grep ":82"
# avc: denied { name_bind } for comm="httpd" src=82
#     scontext=system_u:system_r:httpd_t:s0
#     tcontext=system_u:object_r:reserved_port_t:s0 tclass=tcp_socket

semanage port -l | grep http_port_t
```

**Resolução:**
```bash
semanage port -a -t http_port_t -p tcp 82

# Verificar
semanage port -l | grep "82 "
# http_port_t   tcp   82, 80, 81, 443, ...
```

### 2.4 — Booleans do Apache desativados

**Sintoma:** Apache não consegue atuar como proxy reverso ou o Passenger não consegue mapear memória executável para o runtime Ruby.

**Causa:** Os booleans SELinux controlam permissões do `httpd_t` que não fazem parte do módulo de política principal. Estão desativados por padrão no SLES 16.

**Resolução:**
```bash
# Proxy reverso — necessário para comunicação interna do OBS
setsebool -P httpd_can_network_connect 1
setsebool -P httpd_can_network_relay   1

# Execução de memória mapeável — necessário para Passenger/Ruby
setsebool -P httpd_execmem             1

# Verificar
getsebool httpd_can_network_connect
getsebool httpd_can_network_relay
getsebool httpd_execmem
```

### Aplicação da Política obs-apache

```bash
checkmodule -M -m \
    -o /tmp/obs-apache.mod \
    configs/selinux/obs-apache.te

semodule_package \
    -o /tmp/obs-apache.pp \
    -m /tmp/obs-apache.mod

semodule -i /tmp/obs-apache.pp

# Verificar instalação
semodule -l | grep obs-apache
```

**Comandos auxiliares obrigatórios após o módulo:**
```bash
semanage port -a -t http_port_t -p tcp 82
setsebool -P httpd_can_network_connect 1
setsebool -P httpd_can_network_relay   1
setsebool -P httpd_execmem             1
chcon -R -t cert_t /srv/obs/certs/
chcon -t bin_t /srv/www/obs/api/bin/clockworkd
chcon -t bin_t /srv/www/obs/api/bin/delayed_job
```

---

## Verificação Geral

```bash
# Estado do SELinux
sestatus

# Módulos instalados
semodule -l | grep obs

# Negações recentes
grep -i denied /var/log/audit/audit.log | tail -20

# Filtrar por serviço
grep -i denied /var/log/audit/audit.log | grep bs_redis
grep -i denied /var/log/audit/audit.log | grep httpd

# Booleans do Apache
getsebool -a | grep httpd

# Portas mapeadas
semanage port -l | grep http_port_t
```

Qualquer erro de SELinux em novos serviços está catalogado em [12 — Troubleshooting](12-troubleshooting.md).

---

## Notas para Ambiente de Produção

> Em [`obs-sles16-multinode`](https://github.com/mariosergiosl/obs-sles16-multinode), cada módulo é aplicado apenas no nó onde o serviço opera:
> - `obsredis.te` → nó de Backend
> - `obs-apache.te` → nós de Frontend
>
> Os arquivos `.pp` compilados são distribuídos via automação (Salt/Ansible) e aplicados **antes** da inicialização dos serviços em cada nó. Os comandos `semanage`, `setsebool` e `chcon` também fazem parte do playbook de provisionamento de cada nó.

> Monitore releases futuras do pacote `obs-server` para verificar se políticas SELinux oficiais foram incluídas. Se sim, remova os módulos locais para evitar conflito:
> ```bash
> semodule -r obsredis
> semodule -r obs-apache
> ```
