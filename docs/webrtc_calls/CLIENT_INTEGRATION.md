Интеграция клиента (Flutter) и настройка .env

Файлы и переменные, которые нужно установить в вашем `.env` (в корне приложения):

- MATRIX_ENABLE=true
- MATRIX_HOMESERVER_URL=https://matrix.your.domain
- MATRIX_ACCESS_TOKEN=<long_lived_service_token_or_user_token_for_testing>
- MATRIX_TURN_SERVERS (опционально) — JSON-массив ICE/TURN серверов или CSV списка URL. Пример JSON:

```text
MATRIX_TURN_SERVERS=[{"urls":"turn:your.domain:3478","username":"turnuser","credential":"turnpass"}]
```

Примечания по реализации клиента

- В проект добавлен `CallMatrixService` (lib/services/call_matrix_service.dart). Он реализует простейший сигналинг над событиями комнаты `io.twospace.call.signal` (invite/answer/candidate/hangup).
- Чтобы использовать более безопасный способ (получение временных TURN-учётных данных от Synapse), потребуется доработать `CallMatrixService` чтобы оно запрашивало TURN-credentials через соответствующий endpoint (обычно `/ _matrix/client/v3/voip/turnServer` или нестабильный путь `/ _matrix/client/unstable/voip/turnServer`).

Изменения в коде для production

1. TURN: сейчас клиент читает `MATRIX_TURN_SERVERS` и использует её как `iceServers`. Для production рекомендую использовать Synapse + turn_shared_secret flow (Synapse будет выдавать временные учётные данные) или реализовать запрос на homeserver для получения актуальных TURN-credential-ов.

2. E2EE и приватность: текущая реализация сигнального канала использует открытые room state events; если вы хотите E2EE звонки, потребуется поддержка Megolm/Olm для сигналинга (или шифровать payload в событии). Это не тривиально и требует интеграции с Matrix E2EE.

3. UI/UX: экран звонка уже улучшен: локальный и удалённый превью, кнопки пригласить/завершить/вкл-выкл. Дополнительно можно добавить:
   - индикатор уровня громкости (audio level)
   - переключение аудио-устройств (список устройств через `navigator.mediaDevices.enumerateDevices()`)
   - запись звонков / логирование качества (если требуется)

Если хотите, я добавлю автоматический шаг: при старте приложения запрашивать у Synapse TURN-credentials и обновлять `CallMatrixService` динамически.