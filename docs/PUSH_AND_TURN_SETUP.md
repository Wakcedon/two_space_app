# Настройка push-уведомлений и TURN для TwoSpace

Этот файл содержит краткие рабочие шаги для настройки push (FCM/APNs) и TURN (coturn) для VoIP-звонков и push-уведомлений у Synapse.

Push (Android / iOS)
1. Android (FCM): получите `google-services.json` и Firebase Cloud Messaging Server Key.
   - В Synapse в `homeserver.yaml` добавьте push gateway настройки (пример см. в доках synapse).
   - В приложении установите `firebase_messaging` и настройте `google-services.json`.

2. iOS (APNs): получите p8 ключ от Apple и настройте в Synapse push gateway.

Общая ссылка по настройке push в synapse: https://matrix-org.github.io/synapse/latest/usage-notifications/notifications.html

TURN (coturn)
1. Если у вас есть TURN на том же домене, убедитесь что он отвечает на нужном порту (обычно 3478).
2. Простой тест подключения TURN можно сделать с помощью утилиты `trickle-ice` или с помощью команд в powershell (см. скрипт check_turn.ps1 рядом).

3. В `homeserver.yaml` укажите секцию `turn_uris`, `turn_shared_secret` или `turns` в зависимости от вашей конфигурации.

Пример простого теста в PowerShell (скрипт приведён рядом):

```powershell
# Запустить скрипт check_turn.ps1 с параметром TURN сервера
.
```

Если нужно, могу сгенерировать готовый `check_turn.ps1` для проверки ваших TURN-конфигураций.
