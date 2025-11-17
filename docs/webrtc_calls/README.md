# Включение собственных звонков (WebRTC) — TwoSpace

Это инструкция по развёртыванию и настройке WebRTC-звонков в приложении.
Поскольку ваш Matrix (Synapse) стоит на VPS в `/home/srv/synapse`, команды и правки ниже предполагают, что вы подключаетесь к этой машине и редактируете файлы в этой директории.

Вместо встраивания Jitsi реализована нативная WebRTC-схема с сигналингом через Matrix (пользовательские события `io.twospace.call.signal`).

Что сделано в коде (в проекте):
- Добавлен `CallMatrixService` — простая логика сигналинга по событиям комнаты (invite/answer/candidate/hangup).
- Экран звонка `lib/screens/call_screen.dart` переписан на `flutter_webrtc` (локальное/удалённое превью, кнопки управления).
- Добавлен поддержка TURN/STUN через переменную окружения `MATRIX_TURN_SERVERS`.

Далее описано что нужно сделать на VPS (где у вас установлен Synapse в `/home/srv/synapse`) чтобы звонки работали корректно.

## Короткая последовательность (команды для Ubuntu/Debian)

1) Установить coturn:

```powershell
sudo apt update; sudo apt install -y coturn
```

2) Включить coturn в автозагрузке (Debian/Ubuntu — отредактируйте `/etc/default/coturn`):

```powershell
sudo sed -i 's/^#TURNSERVER_ENABLED=1/TURNSERVER_ENABLED=1/' /etc/default/coturn || echo 'TURNSERVER_ENABLED=1' | sudo tee -a /etc/default/coturn
sudo systemctl enable --now coturn
```

3) Сгенерировать секрет для long-term credentials (вариант "shared secret", Synapse может использовать этот секрет):

```powershell
SECRET=$(openssl rand -hex 32)
echo "TURN secret: $SECRET"
```

4) Отредактировать `/etc/turnserver.conf` (пример):

```text
# /etc/turnserver.conf (основные опции)
listening-port=3478
tls-listening-port=5349
listening-ip=0.0.0.0
relay-ip=<PUBLIC_IP>      # если необходимо указать внешний IP
fingerprint
lt-cred-mech
use-auth-secret
static-auth-secret=$SECRET
realm=your.domain
no-loopback-peers
no-multicast-peers
# диапазон relay-портов (optional, откройте в firewall)
min-port=49152
max-port=65535
# сертификаты (если хотите поддержать TLS на 5349)
# cert=/etc/letsencrypt/live/your.domain/fullchain.pem
# pkey=/etc/letsencrypt/live/your.domain/privkey.pem
```

После правки перезапустите coturn:

```powershell
sudo systemctl restart coturn
sudo systemctl status coturn --no-pager
```

5) Открыть порты в UFW/Firewall и в панели облачного провайдера:

```powershell
sudo ufw allow 3478/tcp
sudo ufw allow 3478/udp
sudo ufw allow 5349/tcp
sudo ufw allow 5349/udp
# если используете диапазон relay-портов:
sudo ufw allow 49152:65535/udp
```

6) Настроить Synapse (homeserver.yaml) чтобы он мог выдавать TURN-данные (пример):

Откройте `homeserver.yaml` и добавьте или обновите секцию:

```yaml
turn_uris:
  - "turn:your.domain:3478?transport=udp"
  - "turn:your.domain:3478?transport=tcp"
turn_shared_secret: "${TURN_SECRET}"
turn_user_lifetime: 86400
# Если хотите чтобы Synapse использовал внешний TURN через static credentials,
# то используйте turn_shared_secret (shared secret) — Synapse будет генерировать
# короткоживущие логины для клиентов.
```

Замените `your.domain` и `TURN_SECRET` на конкретные значения. Если вы установили `static-auth-secret` в `turnserver.conf`, используйте тот же секрет.

Перезапустите Synapse (если установлен как systemd service):

```powershell
sudo systemctl restart matrix-synapse
```

7) Проверка TURN

- Убедитесь, что при запросе к coturn порт 3478 открыт.
- Для отладки можно использовать `trickle`/`coturn` утилиты или WebRTC-internals в браузере.

## Пояснение: два варианта работы с TURN

A) Synapse + turn_shared_secret (рекомендуется)
- Вы настраиваете coturn с `use-auth-secret` и `static-auth-secret`.
- В `homeserver.yaml` прописываете `turn_uris` и `turn_shared_secret` (тот же секрет).
- Synapse умеет выдавать временные TURN-учётные данные клиенту через свой voip/turn endpoint.
- Клиенты (matrix-js-sdk/другие) получают временные credentials автоматически при запросе TURN через Synapse.

B) Статические учётные данные (проще для тестирования)
- В coturn вы можете добавить обычных пользователей (учётные записи) или настроить static users.
- В приложении прописываете `MATRIX_TURN_SERVERS` в `.env` как JSON с `urls`, `username`, `credential`.

Пример (в `.env` приложения):

```text
MATRIX_TURN_SERVERS=[{"urls":"turn:your.domain:3478","username":"turnuser","credential":"turnpass"}]
```

Наш текущий клиентный код поддерживает чтение `MATRIX_TURN_SERVERS` и использует его для `RTCPeerConnection`.

## Деплой сертификата (если нужно TLS для 5349)

Рекомендуется получить сертификат для `your.domain` (Let's Encrypt) и настроить coturn на использование cert/pkey.

Пример с certbot (Debian/Ubuntu):

```powershell
sudo apt install -y certbot
sudo certbot certonly --standalone -d your.domain
# затем укажите в /etc/turnserver.conf
# cert=/etc/letsencrypt/live/your.domain/fullchain.pem
# pkey=/etc/letsencrypt/live/your.domain/privkey.pem
sudo systemctl restart coturn
```

## Проверка работы из клиента

1. Заполните `.env` приложения (в репозитории) сведениями:

```text
MATRIX_ENABLE=true
MATRIX_HOMESERVER_URL=https://matrix.your.domain
MATRIX_ACCESS_TOKEN=<service_or_user_token_for_testing>
MATRIX_TURN_SERVERS=[{"urls":"turn:your.domain:3478","username":"turnuser","credential":"turnpass"}]
```

2. Запустите приложение на телефоне/эмуляторе/десктопе и попробуйте позвонить — приложение использует Signal-over-Matrix events `io.twospace.call.signal`.

3. Для полного production-качества: настройте Synapse turn_shared_secret flow и обновите клиент, чтобы получать временные credentials от homeserver-а (это более безопасно и масштабируемо).

## Что ещё важно

- NAT и firewall: убедитесь, что coturn доступен извне и что публичный IP указан, если сервер за NAT.
- Настройка диапазона relay портов и их открытие в firewall критичны для прохождения RTP.
- Для групповых конференций (более 2 участников) лучше использовать SFU (mediasoup / Janus / Jitsi) — WebRTC P2P будет съедать клиентские ресурсы. Для 1:1 звонков этого обычно достаточно.

## Валидация и тесты

- После настройки проверьте логи `/var/log/turnserver/` (или `journalctl -u coturn`) на наличие ошибок при подключениях.
- В клиенте включите вывод WebRTC internals и проверьте, что ICE candidate-ы проходят и соединение становится `completed`/`connected`.

---

Если хотите — могу автоматически сгенерировать конфигурацию `/etc/turnserver.conf` по вашим параметрам (домен, публичный IP), и подготовить правки `homeserver.yaml` (diff) для Synapse; скажите домен и предпочитаемый способ (shared-secret vs static users).
