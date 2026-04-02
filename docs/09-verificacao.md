# 09 — Verificação Final

Checklist de saúde do stack completo após a instalação.

---

## 1. Status dos Serviços de Backend

```bash
systemctl status \
  redis@default.service \
  obsredis.service \
  obssrcserver.service \
  obsrepserver.service \
  obsdispatcher.service \
  obspublisher.service \
  obsworker.service
```

**Estado esperado para todos:** `Active: active (running)`

---

## 2. Status dos Serviços de Frontend

```bash
systemctl status \
  mariadb.service \
  memcached.service \
  apache2.service \
  obs-api-support.target
```

---

## 3. Verificação de Portas e Bindings

```bash
ss -tulpn | grep -E ':(80|443|82|6379|3306)'
```

**Saída esperada:**

| Porta | Processo |
|-------|----------|
| `0.0.0.0:80` | apache2 |
| `0.0.0.0:443` | apache2 |
| `127.0.0.1:6379` | redis-server |
| `127.0.0.1:3306` | mysqld |

---

## 4. Teste de Saúde do Frontend

```bash
curl -I -k https://localhost/
```

**Resposta esperada:** `HTTP/1.1 200 OK` ou `HTTP/1.1 302 Found` (redirect para login).

---

## 5. Teste da Fila de Jobs Assíncronos

```bash
sudo -u wwwrun RAILS_ENV=production \
  bin/rails runner "puts Delayed::Job.count"
```

Deve retornar um número (0 ou mais) sem erros de conexão.

---

## 6. Verificação de Erros SELinux

```bash
grep -i denied /var/log/audit/audit.log | tail -20
```

Não deve haver novas negações após a aplicação da política em [06 — SELinux](06-selinux.md).

---

## 7. Log de Produção da API

```bash
tail -f /srv/www/obs/api/log/production.log
```

Observe se há erros de `ActiveRecord`, `Redis::ConnectionError` ou `LoadError`.

---

## Resumo do Checklist

- [ ] `redis@default.service` — active (running)
- [ ] `obsredis.service` — active (running)
- [ ] `obssrcserver.service` — active (running)
- [ ] `obsrepserver.service` — active (running)
- [ ] `obsdispatcher.service` — active (running)
- [ ] `mariadb.service` — active (running)
- [ ] `memcached.service` — active (running)
- [ ] `apache2.service` — active (running)
- [ ] `curl -k https://localhost/` retorna HTTP 200/302
- [ ] Sem negações SELinux novas em `audit.log`
- [ ] Sem erros críticos em `production.log`
