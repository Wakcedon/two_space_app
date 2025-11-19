# Настройка OIDC (Google / Yandex) для Synapse (Matrix)

Короткая инструкция по настройке OIDC в Synapse, чтобы пользователи могли логиниться через Google / Yandex.

Важно — заметки по регистрации и ошибкам при перезапуске Synapse
- Если Synapse падает при старте (в логах вы видите `Error in configuration: You have enabled open registration without any verification`), это значит, что в `homeserver.yaml` включена открытая регистрация (`enable_registration: true`) без механизма верификации (email/captcha/token). Synapse защищает администраторов от спама и не будет стартовать до тех пор, пока конфигурация не станет безопасной.

Решения (выберите одно):
- Включить верификацию регистрации (настройка email/captcha/token). Это рекомендуемый путь в продакшене.
- Временно разрешить регистрацию без верификации, добавив в `homeserver.yaml` строку:

```yaml
enable_registration_without_verification: true
```

  Это уберёт проверку и позволит Synapse стартовать, но будьте внимательны — это допускает автоматические регистрации и потенциальный спам.
- Или отключить `enable_registration` и использовать только OIDC/SAML/Synapse registration_shared_secret токен-посредник для регистрации из вашего сервиса.

После изменения конфига перезапустите контейнеры:

```powershell
# в каталоге с docker-compose
docker compose down
docker compose up -d
docker compose logs -f
```

Если вы видите `502 Bad Gateway` от nginx при попытке сделать /register, это обычно означает, что nginx не может достучаться до Synapse (synapse-процесс упал или контейнер перезапускается). Проверьте логи `docker compose logs synapse` и исправьте конфигурацию как описано выше.

Пример секции OIDC (Google) для `homeserver.yaml`:

```yaml
oidc_providers:
  - idp_id: google
    idp_name: Google
    issuer: https://accounts.google.com
    client_id: "ВАШ_GOOGLE_CLIENT_ID"
    client_secret: "ВАШ_GOOGLE_CLIENT_SECRET"
    scopes: ["openid", "email", "profile"]
    enable_registration: true
    claim_map:
      email: email
      preferred_username: sub
    buttons:
      - text: "Войти через Google"
        idp_id: google
        primary: true
```

Для Yandex используйте `issuer: https://oauth.yandex.ru` и похожую конфигурацию.

Redirect URI, который нужно указать в консоли OAuth-приложения:

```
https://<your-homeserver>/_matrix/client/r0/login/sso/redirect
```

Как быстро проверить регистрацию и работу Synapse после правок:

- Проверка доступности TURN (локально):
  - Запустите скрипт `tooling/check_turn.ps1 -turnUri "turn:matrix.apitwospace.ru:3478?transport=udp"` на Windows — скрипт проверит DNS и TCP-порт.

- Прямой тест регистрации (curl):

```bash
curl -i -X POST -H "Content-Type: application/json" -d '{"username":"__test","password":"__test","auth":{"type":"m.login.dummy"}}' https://matrix.apitwospace.ru/_matrix/client/v3/register
```

  - Если вы получаете `HTTP/2 502` — проверьте логи Synapse и nginx; скорее всего Synapse падает на старте из-за конфигурации (см. выше).
  - Если возвращается `403` с телом `{"errcode":"M_FORBIDDEN","error":"Registration has been disabled"}` — регистрация отключена сервером; включите её в `homeserver.yaml` или настройте OIDC.

Дополнительно — TURN/VoIP
- Если вы используете встроенный TURN (секция `turn_uris` и `turn_shared_secret`), проверьте, что `turn_uris` корректно указывает хост/порт и что порт доступен извне. Пример:

```yaml
turn_uris:
  - "turn:apitwospace.ru:3478?transport=udp"
  - "turn:apitwospace.ru:3478?transport=tcp"
turn_shared_secret: "ВАШ_TURN_SHARED_SECRET"
turn_user_lifetime: 86400
```

Если после правок Synapse по-прежнему не стартует — скопируйте часть логов `docker compose logs synapse` сюда, и я подскажу, какие опции исправить.

Полезные ссылки:
- Документация Synapse: https://github.com/matrix-org/synapse/tree/main/docs
- Пример OIDC: https://matrix.org/docs/guides/oidc

Файл с более детальными серверными инструкциями в репозитории: `docs/PUSH_AND_TURN_SETUP.md` (там указаны примеры для push и TURN).
