# 08 — Firewall

Configuração do `firewalld` para exposição dos serviços do OBS.

---

## 1. Abertura de Portas — Frontend (HTTP/HTTPS)

```bash
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload
```

---

## 2. Portas de Comunicação Interna (Topologia Distribuída)

Estas portas são necessárias **apenas em topologias com workers remotos**.
Em single-node, todo o tráfego é interno ao host.

```bash
# Porta do Source Server (obssrcserver)
firewall-cmd --permanent --add-port=5252/tcp

# Porta do Repository Server (obsrepserver)
firewall-cmd --permanent --add-port=5352/tcp

# Porta interna do Apache (usada pelo OBS)
firewall-cmd --permanent --add-port=82/tcp

firewall-cmd --reload
```

> **Nota SELinux:** A porta 82/tcp deve também ser mapeada no contexto SELinux (feito em [06 — Política SELinux](06-selinux.md)):
> ```bash
> semanage port -a -t http_port_t -p tcp 82
> ```

---

## Mapa de Portas por Serviço

| Porta | Protocolo | Serviço | Visibilidade |
|-------|-----------|---------|--------------|
| 80 | TCP | Apache HTTP | Pública (Frontend) |
| 443 | TCP | Apache HTTPS | Pública (Frontend) |
| 82 | TCP | OBS interno (Apache) | Interna |
| 5252 | TCP | obssrcserver | Interna (nós OBS) |
| 5352 | TCP | obsrepserver | Interna (nós OBS) |
| 6379 | TCP | Redis | Somente loopback (lab) / Interna (produção) |
| 3306 | TCP | MariaDB | Interna (nós OBS) |

> **⚠️ Produção:** Em ambientes com múltiplos nós, as portas 5252, 5352, 6379 e 3306 devem ser acessíveis **exclusivamente entre os nós OBS** via regras de firewall com `--source <rede-interna>`. Nunca exponha Redis ou MariaDB para redes externas.
