# Matrix / Synapse setup notes for TwoSpace

Это файл содержит пошаговые инструкции, какие изменения/настройки надо внести на Matrix (Synapse) сервере и сопутствующие сервисы, чтобы приложение TwoSpace корректно работало после миграции с Appwrite.

Важные предпосылки
- Homeserver доступен по домену (например `matrix.apitwospace.ru`). В приложении указывать домен напрямую не нужно — используйте `.env` (`MATRIX_HOMESERVER_URL`).
- Для PoC и тестирования можно временно завести сервисный access token и положить в `MATRIX_ACCESS_TOKEN` (но в продакшене используйте per-user токены через login/OAuth).

1) Основные переменные окружения (в `.env` на стороне приложения)
- MATRIX_ENABLE=true
- MATRIX_HOMESERVER_URL=https://matrix.example.org
- MATRIX_SERVER_NAME=example.org
- MATRIX_ACCESS_TOKEN=<long-lived-service-token-for-testing>
- MATRIX_OAUTH_CLIENT_ID=
- MATRIX_OAUTH_CLIENT_SECRET=
- MATRIX_E2EE_ENABLED=true
- JITSI_SERVER_URL=https://meet.jit.si

2) Создание / получение долгоживущего токена (для PoC)
- Залогиньтесь на сервере Synapse под admin-пользователем или используйте `register_new_matrix_user`/admin API.
- Создайте токен с помощью Admin API (если у вас synapse admin API включён):
  POST /_synapse/admin/v1/register? (или с использованием утилит)
- Альтернативно используйте `generate_registration_token` или настройку `registration_shared_secret`.

3) OAuth / SSO (OpenID Connect)
- Если хотите поддержать вход через внешний OAuth/SSO (Google, GitLab и т.д.), в `homeserver.yaml` добавьте `openid_connect` provider configuration, например:

```yaml
oidc_config:
  enabled: true
  providers:
    - idp_id: myoidc
      issuer: https://accounts.example.com
      client_id: <CLIENT_ID>
      client_secret: <CLIENT_SECRET>
      name: "Example SSO"
      scope: ["openid","profile","email"]
```

- После этого Synapse будет поддерживать перенаправления на IdP. На клиенте нужно инициировать SSO (open a browser to the login URL) и завершить flow. Клиентское приложение должно реализовать обработку redirect и обмен code -> token.

4) Регистрация пользователей / миграция
- Опции:
  - Включить open registration (не рекомендуется в продакшене).
  - Использовать маппинг пользователей: написать мигратор, который читает пользователей из Appwrite и создаёт их на Synapse через Admin API `/_synapse/admin/v2/users`.
  - Или использовать SSO: если у вас централизованный IdP, объедините учетные записи.

5) E2EE (Olm / Megolm)
- E2EE шифрование полностью контролируется клиентом. Сервер ничего не делает, кроме хранения зашифрованных сообщений.
- Клиентская реализация E2EE требует поддержки Olm на клиенте (libolm). Для Flutter это означает:
  - Поддерживаемая SDK (например matrix_sdk) с crypto поддержкой или
  - Использование FFI-обёртки для libolm, либо подключение нативных библиотек в Android/iOS.

- Шаги для production-ready E2EE в приложении:
  - Выбрать Matrix client SDK с поддержкой crypto (на Dart — проверить matrix_sdk возможности; иначе обернуть через platform channels).
  - На Android: добавить `libolm` в `android/app/src/main/jniLibs/<abi>/` или подключить через Gradle/NDK сборку.
  - На iOS: подключить `libolm` через CocoaPods (pod 'libolm') и обновить Podfile.
  - Убедиться, что SDK и сборка поддерживают создание и хранение ключей, экспорт/импорт шифровальных ключей при бекупе и т.п.

6) Push-уведомления (план)
- Synapse может быть настроен на отправку push-уведомлений через push gateway и FCM/APNs.
- Для Android вам потребуется FCM Server Key и конфиг в Synapse (push.gateway.rest.api_key и т.д.). Для iOS — APNs ключ/сертификат.
- Пока отложим: сначала сделаем работу чатов и звонков.

7) Jitsi integration (video calls)
- Для MVP используйте публичный сервер `https://meet.jit.si` — не требует серверных правок.
- Для приватности/надежности рекомендуется self-hosted Jitsi (Debian/Ubuntu пакеты). После установки укажите URL в `.env` (JITSI_SERVER_URL).
- Клиент в приложении будет открывать Jitsi конференцию по URL — можно создавать комнату вида `${server}/${roomName}` и передавать JWT/room password при необходимости.

8) Server-side functions (замена Appwrite Functions)
- В `tooling/functions/` есть несколько node.js функций, использующих Appwrite SDK. Их надо переписать на независимые HTTP-scripts или перевести в бекенд microservices, которые используют Matrix Admin API при необходимости.
- Примеры задач для функций:
  - mirror_message — репликация/модификация сообщений (в Matrix это может быть не нужна, т.к. сервер распределяет события между участниками)
  - search_users — замените вызов Appwrite admin API на ваш собственный user-index (или используйте federated user search через Synapse?)

9) Замечания по безопасности
- Никогда не храните мастер-API-ключи или admin-токены в публичном репозитории. Используйте переменные окружения на CI/CD и секретное хранилище.
- Для production используйте per-user токены (логин) и refresh flows. По возможности интегрируйте SSO.

10) Полезные ссылки
- Synapse (Matrix server) docs: https://matrix.org/docs/guides/ 
- Synapse configuration (homeserver.yaml): https://github.com/matrix-org/synapse/blob/master/docs/homeserver.yaml
- OpenID Connect config for Synapse: https://github.com/matrix-org/synapse/blob/master/docs/openid.md
- Matrix Client-Server API: https://spec.matrix.org/v1.4/client-server-api/
- Jitsi quick install: https://jitsi.org/downloads/

Если хотите, могу подготовить точные команды для установки libolm на Android/iOS и пример `podfile`/gradle конфигурации, а также шаблоны переписанных server functions (Node/Express) для замены Appwrite Functions.
