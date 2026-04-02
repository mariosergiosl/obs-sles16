# 02 — Instalação de Pacotes

Instalação dos componentes centrais do Open Build Service.

---

## 1. Pacotes a Instalar

| Pacote | Função |
|--------|--------|
| `obs-server` | Backend: source server, repo server, dispatcher, publisher, workers |
| `obs-worker` | Agente de compilação local (integra com o dispatcher) |
| `obs-api` | Frontend Rails: API REST, WebUI, Delayed Jobs |

---

## 2. Instalação

```bash
zypper in obs-server obs-worker obs-api
```

**Resolução de Dependências:**

O zypper deve resolver `ghostscript-fonts-std` nativamente via SUSE Package Hub (ativado no passo anterior). **Não quebre dependências** (`option 2`).

Se o prompt de resolução aparecer com `nothing provides 'ghostscript-fonts-std'`, verifique se o Package Hub está ativo:

```bash
zypper lr | grep PackageHub
```

Se ausente, ative-o conforme [01 — Repositórios](01-repositorios.md) e repita a instalação.

---

## 3. Verificar Unidades Systemd Instaladas

Após a instalação, mapeie todos os serviços disponíveis:

```bash
systemctl list-unit-files | grep -E '^obs'
```

> **Nota importante:** O OBS não instala um serviço monolítico `obs-server.service`. A arquitetura é modular — cada componente possui sua própria unidade systemd. Veja a listagem completa em [04 — Serviços de Backend](04-backend.md).

**Serviços principais esperados após instalação:**

```
obsapisetup.service
obsdeltastore.service
obsdispatcher.service
obsdodup.service
obsgetbinariesproxy.service
obsnotifyforward.service
obspublisher.service
obsredis.service
obsrepserver.service
obsscheduler.service
obsservice.service
obsservicedispatch.service
obssignd.service
obssigner.service
obssourcepublish.service
obssrcserver.service
obsstoragesetup.service
obswarden.service
obsworker.service
obs-clockwork.service
obs-delayedjob-queue-*.service (múltiplos)
obs-sphinx.service
obs-api-support.target
```

> **⚠️ Produção:** Em nós dedicados a worker, instale apenas `obs-worker`. Em nós de frontend, instale `obs-api` e `obs-server` (sem `obs-worker`). A separação física impede que picos de CPU durante builds afetem a disponibilidade da WebUI e da API.
