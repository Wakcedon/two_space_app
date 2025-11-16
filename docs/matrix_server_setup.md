## Развёртывание Synapse (Matrix homeserver) — подробная инструкция (рус.)

Ниже — последовательная, практическая инструкция для быстрого развёртывания Synapse (PoC) и получения рабочего access_token, с которым приложение TwoSpace сможет работать в Matrix-режиме. Инструкция ориентирована на Debian/Ubuntu и использует Docker + nginx + Let's Encrypt. Для production потребуется дополнительная безопасность, мониторинг и бэкапы.

Краткий результат после выполнения: доступный по HTTPS homeserver (например, https://matrix.example.org) и сервисный аккаунт с access_token, который можно временно использовать в `.env` приложения. В production вместо сервисного токена рекомендуется реализовать per-user логин (см. раздел «Рекомендации»).

1) Требования

- VPS с Linux (Debian/Ubuntu 22.04+ рекомендовано)
- Домен, указывающий на сервер (A/AAAA). Пример: matrix.example.org
- Открытые порты: 80 (http), 443 (https). Порт 8448 используется для federation и обычно проксируется через 443.
- Установленные Docker и docker-compose (или docker compose plugin).

2) Установка Docker

Выполните (пример для Debian/Ubuntu):

```powershell
sudo apt update; sudo apt install -y docker.io docker-compose
sudo systemctl enable --now docker
```

3) Docker Compose: Synapse + nginx + certbot (пример)

Создадим структуру `/srv/twospace-synapse` и три сервиса: synapse (homeserver), nginx (reverse proxy) и certbot (получение TLS).

Создайте `docker-compose.yml` в `/srv/twospace-synapse` с содержимым:

```yaml
version: '3.8'
services:
  synapse:
    image: matrixdotorg/synapse:latest
    restart: unless-stopped
    volumes:
      - ./synapse-data:/data
    environment:
      - SYNAPSE_SERVER_NAME=matrix.example.org
      - SYNAPSE_REPORT_STATS=no
    expose:
      - "8008"

  nginx:
    image: nginx:stable
    restart: unless-stopped
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./letsencrypt:/etc/letsencrypt
    ports:
      - "80:80"
      - "443:443"
    depends_on:
      - synapse

  certbot:
    image: certbot/certbot
    volumes:
      - ./letsencrypt:/etc/letsencrypt
    entrypoint: ["/bin/sh", "-c", "while true; do sleep 3600; done"]

```

Создайте каталог `nginx/conf.d` и файл `nginx/conf.d/matrix.conf` с примером конфигурации:

```nginx
server {
    listen 80;
    server_name matrix.example.org;

    location /.well-known/matrix/client {
        return 200 '{"m.homeserver":{"base_url":"https://matrix.example.org"}}';
        add_header Content-Type application/json;
    }

    # Redirect all other traffic to https
    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name matrix.example.org;

    ssl_certificate /etc/letsencrypt/live/matrix.example.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/matrix.example.org/privkey.pem;

    # Proxy Matrix client-server API
    location /_matrix {
        proxy_pass http://synapse:8008/_matrix;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Proxy media downloads/uploads (media endpoints live under /_matrix/media/)
    location /_matrix/media/ {
        proxy_pass http://synapse:8008/_matrix/media/;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Теперь инициализируйте и запустите контейнеры:

```powershell
mkdir -p /srv/twospace-synapse/synapse-data /srv/twospace-synapse/nginx/conf.d /srv/twospace-synapse/letsencrypt
cd /srv/twospace-synapse
docker compose up -d
```

При первом старте Synapse создаст базовые файлы конфигурации в `synapse-data`.

4) Получение TLS (Let's Encrypt)

Используем `certbot` контейнер для получения сертификата (это вручную выполняемый шаг один раз):

```powershell
docker compose run --rm certbot certonly --webroot -w /var/www/html -d matrix.example.org --email your@example.org --agree-tos --no-eff-email
```

Вариант: можно настроить временный webroot в nginx для прохождения проверки или использовать standalone режим certbot (останавливает nginx на время проверки).

После успешного получения сертификата файлы появятся в `letsencrypt/live/matrix.example.org/` и nginx должен удачно проксировать трафик.

5) Создание аккаунта администратора и получение access token

Самый быстрый способ — создать учётку администратора с помощью утилиты `register_new_matrix_user` внутри контейнера synapse:

```powershell
docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008 @admin:matrix.example.org --admin
```

Задайте пароль при создании. Затем получите access token через REST API (на машине с доступом к Synapse):

```powershell
curl -s -XPOST "https://matrix.example.org/_matrix/client/v3/login" -H 'Content-Type: application/json' -d '{"type":"m.login.password","user":"admin","password":"YOURPASS"}' | jq .
```

В ответе будет поле `access_token`. Его можно временно положить в `.env` как `MATRIX_ACCESS_TOKEN` для PoC.

6) Пример .env (ключевые переменные для TwoSpace)

В приложении TwoSpace установите переменные окружения или создайте файл `.env` (не коммитить в VCS). Минимальные переменные:

```
MATRIX_ENABLE=true
MATRIX_HOMESERVER_URL=https://matrix.example.org
MATRIX_SERVER_NAME=matrix.example.org
MATRIX_ACCESS_TOKEN=<админский_или_сервисный_токен>
```

Примечание: использование единого админ/сервисного токена удобно для PoC. В production **не безопасно** хранить глобальный админ-токен в клиентском приложении. Для production:

- Реализуйте per-user логин (Matrix password/login flow или OAuth on the homeserver) и храните access_token в защищённом хранилище (Secure Storage) на клиенте.
- Ограничьте права сервисного токена (используйте прокси-сервис с узким набором возможностей), либо используйте application services if needed.

7) Работа с медиа (аватары / файлы)

- При загрузке файлов (аватаров, изображений в сообщениях) Matrix возвращает `mxc://<server>/<mediaId>` URI. Для получения байтов через HTTP нужно использовать медиа endpoint: `/_matrix/media/v3/download/<server>/<mediaId>`.
- Убедитесь, что `AppwriteService.getFileViewUrl` и виджеты `UserAvatar`/`MediaPreview` умеют конвертировать `mxc://` в корректный URL и передавать заголовок Authorization: Bearer <token> если сервер требует (в конфигурации Synapse обычно медиа публичны, но если приватные — потребуется токен).

8) Тестирование и отладка

- Запустите TwoSpace с `MATRIX_ENABLE=true` и проверьте:
  - Авторизацию (если вы ещё не реализовали per-user login — используйте сервисный токен).
  - Синхронизацию `/sync` (Realtimeservice должен успешно подключиться и получать события).
  - Отображение аватаров и загрузку медиа.

9) Рекомендации по production

- Не храните глобальные админ-токены в клиентских релизах.
- Используйте per-user токены и реализуйте refresh/rotation. Храните токены в secure storage.
- Настройте бэкапы: `homeserver.db` (если sqlite) или Postgres dump + каталог media.
- Настройте мониторинг (Prometheus, alerting) и логи.

Если нужно — могу подготовить готовые скрипты и автоматизацию (ansible / terraform / docker-compose) под ваш домен и требования безопасности.
