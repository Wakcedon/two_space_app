# Настройка приглашений через Matrix для TwoSpace

## Описание

Этот документ описывает, как настроить систему приглашений (invite links) для групповых чатов в TwoSpace на вашем Matrix/Synapse сервере.

## Архитектура приглашений

### Формат ссылки

```
https://YOUR_MATRIX_SERVER_URL/join/[INVITE_CODE]
```

Пример: `https://matrix.example.com/join/A1B2C3D4E5F6`

### Как работает система

1. **Создание ссылки приглашения**
   - Администратор/владелец группы создаёт ссылку
   - Генерируется уникальный 12-значный код (SHA256 хеш)
   - Информация сохраняется в Matrix room state событиях
   - Ссылка становится доступной другим пользователям

2. **Использование ссылки**
   - Пользователь переходит по ссылке
   - Приложение парсит код и передаёт его в Matrix API
   - Проверяются условия (активна ли ссылка, не истёк ли срок, не превышен ли лимит)
   - Пользователь присоединяется к комнате
   - Счётчик использований увеличивается на 1

3. **Статистика**
   - Для администраторов доступна информация о каждой ссылке
   - Показывается количество использований
   - Можно отключить ссылку в любой момент

## Настройка на сервере

### 1. Создание обработчика для `/join/[code]`

Если вы используете **reverse proxy (Nginx/Apache)**, создайте обработчик для перенаправления на приложение:

#### Nginx пример:

```nginx
# В конфиге вашего nginx (например, /etc/nginx/sites-available/default)

location ~ ^/join/([A-Z0-9]+)$ {
    # Перенаправляем на приложение (если оно веб-приложение)
    # Или просто возвращаем JSON с кодом для мобильного приложения
    
    # Для мобильного приложения - возвращаем код:
    if ($request_method = GET) {
        add_header 'Content-Type' 'application/json';
        return 200 '{"invite_code":"$1","matrix_server":"https://matrix.example.com"}';
    }
}
```

#### Apache пример:

```apache
# В конфиге виртуального хоста (.htaccess или конфиг)

<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteRule ^join/([A-Z0-9]+)$ /api/invite.php?code=$1 [L]
</IfModule>
```

### 2. Backend API для обработки приглашений

Если вы хотите фронтенд логику на сервере, создайте простой API:

#### PHP пример (`/api/invite.php`):

```php
<?php
header('Content-Type: application/json');

$code = $_GET['code'] ?? null;

if (!$code || !preg_match('/^[A-Z0-9]{12}$/', $code)) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid invite code']);
    exit;
}

// Здесь можно добавить логику получения информации о приглашении
// из Matrix сервера (если нужно)

echo json_encode([
    'invite_code' => $code,
    'matrix_server' => 'https://matrix.example.com',
    'status' => 'valid'
]);
?>
```

#### Python пример (Flask):

```python
from flask import Flask, jsonify, request
import re

app = Flask(__name__)
MATRIX_SERVER = 'https://matrix.example.com'

@app.route('/join/<invite_code>', methods=['GET'])
def get_invite_info(invite_code):
    # Проверяем формат кода
    if not re.match(r'^[A-Z0-9]{12}$', invite_code):
        return jsonify({'error': 'Invalid invite code'}), 400
    
    # Здесь можно получить информацию о приглашении из Matrix
    # и вернуть превью группы
    
    return jsonify({
        'invite_code': invite_code,
        'matrix_server': MATRIX_SERVER,
        'status': 'valid'
    })

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
```

### 3. Получение превью группы перед присоединением

Для показа информации о группе перед вступлением, используйте Matrix Client API:

#### Endpoint:

```
GET /_matrix/client/v1/room_summary/{roomId}
```

#### cURL пример:

```bash
curl -X GET \
  'https://matrix.example.com/_matrix/client/v1/room_summary/!abc123:matrix.example.com'
```

#### Ответ:

```json
{
  "avatar_url": "mxc://matrix.example.com/abc123",
  "guest_can_join": true,
  "join_rule": "invite",
  "name": "TwoSpace Team",
  "num_joined_members": 42,
  "room_id": "!abc123:matrix.example.com",
  "topic": "General discussion",
  "world_readable": false
}
```

### 4. Синхронизация ролей с Matrix Power Levels

Система использует Matrix power levels для управления ролями:

- **Owner (Владелец)**: Power Level = 100
- **Admin (Администратор)**: Power Level = 50
- **Member (Участник)**: Power Level = 0
- **Guest (Гость)**: Power Level = -1 (если не присоединился)

#### Установка power levels при создании комнаты:

```json
{
  "ban": 50,
  "events": {
    "m.room.avatar": 50,
    "m.room.canonical_alias": 50,
    "m.room.encryption": 100,
    "m.room.history_visibility": 100,
    "m.room.join_rules": 100,
    "m.room.name": 50,
    "m.room.power_levels": 100,
    "m.room.topic": 50
  },
  "events_default": 0,
  "invite": 0,
  "kick": 50,
  "notifications": {
    "room": 50
  },
  "redact": 50,
  "state_default": 50,
  "users": {
    "@owner:matrix.example.com": 100
  },
  "users_default": 0
}
```

## Безопасность

### 1. Ограничение использования ссылок

- **Max Uses**: Ограничение на количество использований (например, 100 или -1 для неограниченно)
- **Expiration**: Ссылка автоматически ухолдится через заданный период (например, 7 дней)
- **Deactivation**: Администратор может отключить ссылку в любой момент

### 2. Проверка подлинности

Все операции с Matrix требуют авторизации через access token:

```bash
curl -X POST \
  'https://matrix.example.com/_matrix/client/v3/rooms/%21abc123%3Amatrix.example.com/join' \
  -H 'Authorization: Bearer syt_user_abcd1234' \
  -H 'Content-Type: application/json'
```

### 3. Rate Limiting

На reverse proxy установите rate limiting для `/join/` endpoint:

#### Nginx пример:

```nginx
limit_req_zone $binary_remote_addr zone=join_limit:10m rate=5r/s;

location ~ ^/join/ {
    limit_req zone=join_limit burst=10 nodelay;
    # ... остальная конфигурация
}
```

## Полный пример работы с приглашениями в Flutter

### 1. Создание приглашения:

```dart
final invite = await groupService.createInviteLink(
  roomId,
  maxUses: 100,
  expiresIn: Duration(days: 7),
);

final joinUrl = 'https://matrix.example.com/join/${invite.inviteCode}';
```

### 2. Использование приглашения:

```dart
// Приложение получает код из ссылки
final inviteCode = 'A1B2C3D4E5F6';

// Показываем превью группы
final roomSummary = await matrixClient.request(
  RequestType.GET,
  '/client/v1/room_summary/$roomId',
);

// Используем ссылку
await groupService.useInviteLink(roomId, inviteCode);
```

### 3. Deep linking (опционально):

Добавьте в `android/app/AndroidManifest.xml`:

```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="https" android:host="YOUR_DOMAIN" android:pathPrefix="/join/" />
</intent-filter>
```

## Мониторинг и логирование

### 1. Логирование в Matrix audit log

Все действия с пригласительными ссылками сохраняются как Matrix state events:

```
Type: com.twospace.invite.link
State Key: [INVITE_CODE]
Content: {
  "invite_code": "A1B2C3D4E5F6",
  "created_by": "@admin:matrix.example.com",
  "created_at": "2024-01-15T10:30:00Z",
  "max_uses": 100,
  "current_uses": 42,
  "is_active": true,
  "expires_at": "2024-01-22T10:30:00Z"
}
```

### 2. Статистика в Synapse

Используйте Synapse REST API для получения статистики:

```bash
curl -X GET \
  'https://matrix.example.com/_synapse/admin/v1/statistics' \
  -H 'Authorization: Bearer YOUR_ADMIN_TOKEN'
```

## Troubleshooting

### Ошибка: "Invite code not found"

**Решение**: Убедитесь, что:
1. Код передан в правильном формате (12 символов, только буквы/цифры)
2. Ссылка была создана в правильной комнате
3. Matrix сервер работает корректно

### Ошибка: "Invite link has expired"

**Решение**: Попросите владельца группы создать новую ссылку с более длительным сроком действия.

### Ошибка: "Invite link usage limit exceeded"

**Решение**: Попросите владельца группы создать новую ссылку с большим лимитом использований.

## Контакты и поддержка

Если у вас есть вопросы по настройке приглашений, обратитесь к документации Matrix:
- https://spec.matrix.org/latest/client-server-api/#joining-rooms
- https://spec.matrix.org/latest/client-server-api/#room-membership

---

**Версия документации**: 1.0
**Дата обновления**: 2024-01-15
