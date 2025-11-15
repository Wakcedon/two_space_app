# Развёртывание Synapse (Matrix homeserver) на VPS — краткая инструкция

Ниже — минимальная последовательность шагов, чтобы развернуть Synapse на вашем VPS (Ubuntu/Debian) с TLS и подготовить sevice account/token для использования приложением TwoSpace.

Важно: это инструкция для быстрого старта (PoC). Для production рекомендуются дополнительные шаги: мониторинг, бэкапы, резервирование, политика retention и отказоустойчивость.

1) Подготовка окружения

- Убедитесь, что у вас есть доменное имя, указывающее на VPS (A/AAAA). Пример: matrix.example.org
- Откройте порты 443 (HTTPS), 8448 (Matrix federation, можно проксировать через 443), 8008 (локальный Synapse http) при необходимости.

2) Установка Docker (рекомендую docker-compose)

```powershell
# на Debian/Ubuntu (powershell команду выполняйте в shell)
sudo apt update; sudo apt install -y docker.io docker-compose
sudo systemctl enable --now docker
```

3) Пример docker-compose.yml (простая конфигурация Synapse)

Создайте `/srv/synapse/docker-compose.yml` со следующим содержимым:

```yaml
version: '3.7'
services:
  synapse:
    image: matrixdotorg/synapse:latest
    restart: unless-stopped
    volumes:
      - ./data:/data
    environment:
      - SYNAPSE_SERVER_NAME=matrix.example.org    # замените на ваш домен
      - SYNAPSE_REPORT_STATS=no
    ports:
      - "8008:8008"
      - "8448:8448"
```

Запустите:

```powershell
cd /srv/synapse
mkdir -p data
docker compose up -d
```

4) Инициализация конфигурации Synapse

При первом запуске в `data` появится конфиг synapse. Для удобства можно использовать `python -m synapse.app.homeserver` если устанавливали из pip, но в Docker образе уже есть утилиты. Инструкция выше создаст базовую структуру.

5) Настройка HTTPS (рекомендация — использовать обратный прокси nginx и Let's Encrypt)

- Установите nginx, и настройте проксирование / SSL через certbot. Вариант:

```nginx
server {
    listen 443 ssl http2;
    server_name matrix.example.org;

    ssl_certificate /etc/letsencrypt/live/matrix.example.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/matrix.example.org/privkey.pem;

    location /_matrix {
        proxy_pass http://127.0.0.1:8008/_matrix;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $host;
    }
}

server {
    listen 80;
    server_name matrix.example.org;
    location / {
        return 301 https://$host$request_uri;
    }
}
```

Затем получите сертификат с certbot и перезапустите nginx.

6) Создание администратора и получение access token

- Можно создать администратора через утилиту `register_new_matrix_user` внутри Docker:

```powershell
docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008 @admin:matrix.example.org --admin
```

Установите пароль при создании. После этого зайдите как админ через клиент (например Element web), войдите и получите access token для админ‑учётки.

Получить токен можно через REST (пример):

```powershell
# замените логин/пароль своими
curl -XPOST "http://localhost:8008/_matrix/client/v3/login" -H 'Content-Type: application/json' -d '{"type":"m.login.password","user":"admin","password":"YOURPASS"}'
```

В ответе будет `access_token`. Скопируйте его и поместите в `.env` как MATRIX_ACCESS_TOKEN.

7) Настройка CORS и .well-known (опционально)

- Если хотите, чтобы клиенты могли автоконфигурироваться, разместите `/.well-known/matrix/client` с ключом `m.homeserver.base_url` у корня домена.

8) Переменные окружения для приложения TwoSpace

- В `.env` приложения (или в окружении запуска) установите:

```
MATRIX_ENABLE=true
MATRIX_HOMESERVER_URL=https://matrix.example.org
MATRIX_SERVER_NAME=matrix.example.org
MATRIX_ACCESS_TOKEN=<tokentaken_from_login>
```

9) Тестирование

- Запустите приложение TwoSpace и используйте ChatMatrixService (в режиме PoC сервис ожидает MATRIX_ENABLE=true). Приложение будет пытаться вызвать /sync и другие endpoint'ы.

10) Дальнейшие шаги (рекомендации)

- Настроить per-user логин в приложении (вместо единого сервисного токена): реализовать Matrix login flow в `AuthService` и хранить access_token per-user.
- Организовать безопасное хранение токенов (secure storage) и rotation/refresh.
- Настроить бэкапы каталога Synapse (`data`), особенно homeserver.db/postgres репозитории и media store.
- Если будете использовать federation, добавьте SPF/DKIM и убедитесь, что порт 8448 открыт и синхронизирован с TLS.

Если хотите, могу подготовить docker-compose с nginx и certbot (с примером конфигурации) и скрипты автоматической инициализации админ‑пользователя.
