# 05 — Redis

Instalação, configuração e integração do Redis com o Open Build Service.

---

## Por que o OBS usa Redis?

O Redis atua como **broker de mensagens e fila de jobs assíncronos** (background jobs).

O frontend Rails do OBS usa o Redis para gerenciar tarefas como:
- Cálculo de dependências pesadas
- Envio de e-mails de notificação
- Atualização de permissões
- Sincronização com LDAP
- Rastreamento de issues (SCM)

O serviço `obsredis` (backend) encaminha eventos internos do motor de compilação para essa fila em memória, evitando gargalos no MariaDB.

> **Histórico:** O Redis foi introduzido no OBS a partir da série 2.10+ para substituir filas baseadas em banco de dados relacional, que não escalavam em ambientes com alta concorrência de builds.

---

## 1. Instalação do Redis

```bash
zypper in redis
```

O pacote no SLES 16 / Package Hub instala a versão 8.x (`redis-8.2.3-bp160.x`).

---

## 2. Configuração da Instância

> **Atenção:** No SLES 16, o Redis usa **instâncias systemd** (`redis@.service`), não um serviço singleton `redis.service`. O arquivo de configuração da instância `default` não é criado automaticamente na instalação.

Crie o arquivo de configuração da instância `default`:

```bash
cp /etc/redis/redis.default.conf.template /etc/redis/default.conf
chown redis:redis /etc/redis/default.conf
```

O arquivo de template está em `/etc/redis/redis.default.conf.template`.
O diretório `/etc/redis/` também contém um subdiretório `includes/` e `sentinel.defaults.conf.template`.

> Veja o arquivo versionado em [`configs/redis/default.conf`](../configs/redis/default.conf).

---

## 3. Ativação do Serviço Redis

```bash
systemctl enable --now redis@default.service
systemctl status redis@default.service
```

**Saída esperada:**
```
● redis@default.service - Redis instance: default
   Active: active (running)
   Status: "Ready to accept connections"
   Main PID: XXXX (redis-server)
```

O Redis escuta em `127.0.0.1:6379` (loopback) e `[::1]:6379`.

---

## 4. Configuração do Backend OBS para o Redis

> **Problema identificado:** A versão Unstable do OBS para SLES 16 alterou silenciosamente:
> 1. O nome da variável: de `$redis_server` para **`$redisserver`** (sem sublinhado)
> 2. O formato do valor: de `IP:porta` para **URI com esquema `redis://`**
>
> O código-fonte confirma na linha 254 de `/usr/lib/obs/server/bs_redis`:
> ```perl
> die("No redis server configured\n") unless $BSConfig::redisserver;
> die("Redis server must be of scheme redis[s]://<server>[:port]\n")
>   unless $BSConfig::redisserver =~ /^(rediss?):\/\/.../;
> ```

### Opção A — BSConfig.local.pm (Recomendada para Lab e Produção)

Crie o arquivo de configuração local (persistente em atualizações de pacote):

```bash
cat <<EOF > /usr/lib/obs/server/BSConfig.local.pm
package BSConfig;

# Redis server endpoint
# Lab:      redis://127.0.0.1:6379
# Produção: redis://<IP-do-no-redis>:6379
\$redisserver = 'redis://127.0.0.1:6379';

1;
EOF

chown obsrun:obsrun /usr/lib/obs/server/BSConfig.local.pm
chmod 644 /usr/lib/obs/server/BSConfig.local.pm
```

> **Nota:** Verifique se `BSConfig.pm` possui o hook de carregamento do `.local.pm`:
> ```bash
> grep "local.pm" /usr/lib/obs/server/BSConfig.pm
> ```
> Se ausente, use a Opção B.

### Opção B — Patch Direto no BSConfig.pm (Fallback)

Se o `BSConfig.local.pm` for ignorado:

```bash
sed -i "s/^1;$/\$redisserver = 'redis:\/\/127.0.0.1:6379';\n1;/" \
  /usr/lib/obs/server/BSConfig.pm
```

> **⚠️ Atenção:** Edições diretas em `/usr/lib/obs/server/BSConfig.pm` são sobrescritas em atualizações do pacote `obs-server`. Prefira sempre o `.local.pm`.

Veja o arquivo versionado em [`configs/BSConfig.local.pm`](../configs/BSConfig.local.pm).

---

## 5. Ajuste de Permissões do Diretório de Eventos

```bash
chown -R obsrun:obsrun /srv/obs
```

---

## 6. Inicialização do obsredis

```bash
systemctl restart obsredis.service
systemctl status obsredis.service
```

**Saída esperada:**
```
● obsredis.service - OBS redis forwarder
   Active: active (running)
   Main PID: XXXX (bs_redis)
```

> **⚠️ Atenção:** O `obsredis.service` requer que a política SELinux esteja aplicada. Consulte [06 — Política SELinux](06-selinux.md) antes de tentar subir este serviço.

---

## Notas para Ambiente de Produção

> **Servidor dedicado:** O Redis **deve** operar em um servidor (ou cluster) dedicado para evitar contenção de RAM e I/O com os processos de build e com o MariaDB. Configure `$redisserver = 'redis://<IP-dedicado>:6379';`.

> **Persistência em disco:** Edite `/etc/redis/default.conf` e habilite persistência AOF ou RDB:
> ```
> appendonly yes
> appendfsync everysec
> ```
> Isso previne perda de filas de jobs em caso de reinicialização abrupta.

> **Autenticação:** Em produção, configure `requirepass <senha>` no Redis e ajuste a URI para `redis://:<senha>@<IP>:6379` no BSConfig.
