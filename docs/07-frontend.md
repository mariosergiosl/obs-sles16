# 07 — Frontend — Apache + Passenger

O frontend do OBS é uma aplicação Ruby on Rails servida pelo **Apache HTTPD** com o módulo **Phusion Passenger**.

---

## 1. Habilitação de Módulos do Apache

```bash
a2enmod ssl
a2enmod headers
a2enmod rewrite
a2enmod proxy
a2enmod proxy_http
a2enmod rewrite proxy proxy_http headers socache_shmcb ssl passenger
```

---

## 2. Verificação dos Templates de VirtualHost

```bash
ls -la /etc/apache2/vhosts.d/ | grep obs
```

O pacote instala templates como `obs.conf.template`. Ative-os:

```bash
mv /etc/apache2/vhosts.d/obs.conf.template /etc/apache2/vhosts.d/obs.conf
```

---

## 3. Declaração do Módulo Passenger

Crie o arquivo de configuração do Passenger:

```bash
cat <<EOF > /etc/apache2/conf.d/passenger.conf
LoadModule passenger_module /usr/lib64/apache2/mod_passenger.so
<IfModule mod_passenger.c>
  PassengerRoot /etc/passenger/locations.ini
  PassengerDefaultRuby /usr/bin/ruby.ruby3.4
</IfModule>
EOF
```

Veja o arquivo versionado em [`configs/apache/passenger.conf`](../configs/apache/passenger.conf).

---

## 4. Ajuste do VirtualHost (obs.conf)

Corrija diretivas depreciadas e aponte o DocumentRoot para o diretório público do Passenger:

```bash
# Comentar diretivas depreciadas
sed -i 's/.*XForward.*/#&/' /etc/apache2/vhosts.d/obs.conf
sed -i 's/.*PassengerPreStart.*/#&/' /etc/apache2/vhosts.d/obs.conf

# Corrigir DocumentRoot
sed -i 's|DocumentRoot .*|DocumentRoot /srv/www/obs/api/public|g' \
  /etc/apache2/vhosts.d/obs.conf

# Remover bloco Directory antigo
sed -i '/<Directory \/srv\/www\/obs\/api\/public>/,/<\/Directory>/d' \
  /etc/apache2/vhosts.d/obs.conf

# Inserir novo bloco Directory antes do fechamento do VirtualHost
sed -i '/<\/VirtualHost>/i \
<Directory /srv/www/obs/api/public>\
  AllowOverride all\
  Options -MultiViews\
  Require all granted\
</Directory>' /etc/apache2/vhosts.d/obs.conf

# Ajustar proprietário dos arquivos da API
chown -R wwwrun:www /srv/www/obs/api
```

---

## 5. Geração de Certificado TLS (Auto-assinado — Lab)

```bash
mkdir -p /srv/obs/certs

openssl req -new -x509 -nodes \
  -out /srv/obs/certs/server.crt \
  -keyout /srv/obs/certs/server.key \
  -days 365 \
  -subj "/CN=sles16BBOBS.lab"

chown root:www /srv/obs/certs/server.*
chmod 640 /srv/obs/certs/server.key

# Rotular com contexto SELinux adequado para leitura pelo Apache
chcon -R -t cert_t /srv/obs/certs/
chmod o+rx /srv /srv/obs
```

> **⚠️ Produção:** Utilize certificados assinados por CA interna ou pública (Let's Encrypt). Armazene a chave privada com permissão 640 e contexto SELinux `cert_t`.

---

## 6. Instalação do Memcached

O Rails exige o Memcached para armazenamento de cookies de sessão. Sem ele, a renderização da interface falha silenciosamente com HTTP 400.

```bash
zypper install -y memcached
systemctl enable --now memcached.service
```

---

## 7. Ativação Global de SSL e Inicialização

```bash
sed -i 's/APACHE_SERVER_FLAGS=""/APACHE_SERVER_FLAGS="SSL"/' \
  /etc/sysconfig/apache2

systemctl enable --now apache2.service
```

---

## 8. Inicialização dos Serviços de Frontend (Delayed Jobs)

```bash
systemctl enable --now obs-api-support.target
```

Este target ativa os seguintes daemons de processamento assíncrono:
- `obs-clockwork.service`
- `obs-delayedjob-queue-default.service`
- `obs-delayedjob-queue-mailers.service`
- `obs-delayedjob-queue-consistency_check.service`
- (e demais filas conforme o target)

---

## 9. Permissões dos Binários Ruby (SELinux)

Se o `obs-clockwork` ou outros binários Ruby falharem com `status=203/EXEC`, corrija o contexto SELinux:

```bash
# Dar permissão de execução nos binários Ruby da aplicação
chmod +x /srv/www/obs/api/bin/clockworkd

# Ajustar contexto para bin_t (execução plena)
chcon -t bin_t /srv/www/obs/api/bin/clockworkd
```

---

## 10. Verificação Final do Frontend

```bash
# Verificar se o Apache subiu corretamente
systemctl status apache2.service

# Testar resposta HTTPS local
curl -I -k https://localhost/

# Monitorar log de produção
tail -f /srv/www/obs/api/log/production.log
```

---

## Notas para Ambiente de Produção

> **TLS:** Configure um certificado válido (CA corporativa ou pública) e desative SSLv3/TLSv1.0. Use apenas TLS 1.2+.

> **Passenger:** Ajuste `PassengerMaxPoolSize` conforme a memória disponível no nó de frontend. Cada processo Passenger consome ~150-250 MB de RAM.

> **Memcached:** Em clusters com múltiplos nós de frontend, configure todos apontando para o mesmo cluster Memcached. Sessões inconsistentes entre nós causam logouts inesperados.
