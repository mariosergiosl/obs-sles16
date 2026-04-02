# 04 — Serviços de Backend

O backend do OBS é composto por múltiplos daemons independentes gerenciados pelo systemd.
Não existe um serviço monolítico `obs-server.service`.

---

## 1. Mapa de Serviços de Backend

| Serviço | Daemon | Função |
|---------|--------|--------|
| `obsstoragesetup.service` | (setup) | Prepara estrutura de diretórios em `/srv/obs` e permissões do usuário `obsrun` |
| `obsapisetup.service` | (setup) | Configuração base da API e do Redis |
| `obsredis.service` | `bs_redis` | Forwarder de eventos do motor de build para a fila Redis |
| `obssrcserver.service` | `bs_srcserver` | Source Repository Server — gerencia código-fonte dos pacotes |
| `obsrepserver.service` | `bs_repserver` | Repository Server — armazena binários compilados e metadados |
| `obsdispatcher.service` | `bs_dispatch` | Dispatcher — distribui jobs de build para os workers disponíveis |
| `obspublisher.service` | `bs_publish` | Publisher — publica repositórios de pacotes após builds bem-sucedidos |
| `obsscheduler.service` | `bs_sched` | Scheduler — calcula dependências e agenda builds |
| `obsworker.service` | `bs_worker` | Worker local — executa builds em chroots isolados |
| `obswarden.service` | `bs_warden` | Warden — monitora workers e reinicia em caso de falha |
| `obssigner.service` | `bs_sign` | Assinatura GPG dos pacotes publicados |

---

## 2. Ordem de Inicialização (Single-Node)

Execute os serviços na seguinte ordem:

### Passo 1 — Preparação de Armazenamento

```bash
systemctl start obsstoragesetup.service
systemctl start obsapisetup.service
```

> Estes são serviços do tipo `oneshot` — executam uma vez e encerram. Não ficam ativos continuamente.

### Passo 2 — Serviços Centrais de Backend

```bash
systemctl enable --now \
  obsredis.service \
  obssrcserver.service \
  obsrepserver.service \
  obsdispatcher.service
```

> **Atenção:** O `obsredis.service` depende do Redis estar operacional. Consulte [05 — Redis](05-redis.md) antes de executar este passo.

### Passo 3 — Serviços Auxiliares

```bash
systemctl enable --now \
  obspublisher.service \
  obsscheduler.service \
  obsworker.service \
  obswarden.service
```

---

## 3. Verificação de Status

```bash
systemctl status \
  obsredis.service \
  obssrcserver.service \
  obsrepserver.service \
  obsdispatcher.service \
  obspublisher.service \
  obsworker.service
```

**Logs dos serviços de backend:**

```bash
ls -la /srv/obs/log/
tail -f /srv/obs/log/src_server.log
tail -f /srv/obs/log/rep_server.log
tail -f /srv/obs/log/dispatcher.log
```

---

## 4. Aviso Benigno no Startup

O `obssrcserver.service` emite o seguinte aviso no log, que é **não-fatal**:

```
Name "BSConfig::localarch" used only once: possible typo at
/usr/lib/obs/server/bs_srcserver line 1995.
```

Este é um aviso de sintaxe Perl sem impacto operacional.

---

## Notas para Ambiente de Produção

> **Separação de serviços:** Em topologia distribuída, `obssrcserver`, `obsrepserver` e `obsdispatcher` operam no nó de backend. Os `obsworker` operam em nós dedicados. A porta `5252/tcp` (srcserver) e `5352/tcp` (repserver) devem estar liberadas no firewall de rede interna entre os nós.

> **Monitoramento de I/O:** Inicie o monitoramento de consumo de I/O em `/srv/obs` assim que os serviços de backend subirem. Use `iostat -x 5` ou integre com o agente de monitoramento da organização.
