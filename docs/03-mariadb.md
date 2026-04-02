# 03 — Banco de Dados (MariaDB)

Provisionamento do banco de dados `api_production` para o frontend Rails do OBS.

---

## 1. Inicialização do Serviço MariaDB

```bash
systemctl enable mariadb
systemctl start mariadb
```

**Verificação:**

```bash
systemctl status mariadb
```

> **Nota:** O binário `mysql` gera um aviso de depreciação no SLES 16 (`Deprecated program name. Use '/usr/bin/mariadb' instead`). Este aviso é esperado e não indica falha.

---

## 2. Criação do Banco e Usuário de Serviço

> **Nota importante:** O utilitário `/usr/sbin/obs-api-setup` existe apenas nas imagens pré-compiladas (OBS Appliance). Em instalações via repositório no SLES 16, o provisionamento é manual.

Execute o script SQL de inicialização:

```bash
mysql -u root -e "
  CREATE DATABASE api_production;
  CREATE USER 'obs'@'localhost' IDENTIFIED BY 'opensuse';
  GRANT ALL PRIVILEGES ON api_production.* TO 'obs'@'localhost';
  FLUSH PRIVILEGES;
"
```

> **⚠️ Produção (senha):** Substitua `'opensuse'` por uma senha forte gerada com `openssl rand -base64 32`. Armazene no vault de credenciais da organização.

---

## 3. Aplicação do Schema Rails

Popule as tabelas lógicas e dados iniciais:

```bash
cd /srv/www/obs/api && RAILS_ENV=production /usr/bin/rake db:setup
```

**Saída esperada (resumida):**
```
Seeding architectures table...
Seeding configurations table...
Seeding roles table...
Seeding users table...
Seeding roles_users table...
Seeding static_permissions table...
Seeding attrib_namespaces table...
Seeding attrib_types table...
Seeding issue trackers ...
```

A ausência de erros confirma o provisionamento completo.

---

## 4. Ajuste das Credenciais no database.yml

Confirme que o arquivo de conexão Rails aponta para o banco criado:

```bash
grep -A5 'production:' /srv/www/obs/api/config/database.yml
```

O campo `password` deve corresponder à senha definida no passo 2.

---

## Notas para Ambiente de Produção

> **Segurança:** Execute `/usr/bin/mysql_secure_installation` **antes** do provisionamento da API para remover contas anônimas e bases de dados de teste.

> **Performance:** Edite `/etc/my.cnf` e configure:
> ```ini
> [mysqld]
> innodb_buffer_pool_size = 70%  # 60-70% da RAM dedicada ao nó DB
> ```

> **Alta Disponibilidade:** O MariaDB deve operar em um servidor dedicado ou em cluster Galera (ativo-ativo) para ambientes com SLA de disponibilidade. Separe fisicamente o nó de banco dos nós de aplicação.
