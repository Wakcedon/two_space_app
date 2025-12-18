# 🔧 Руководство по миграции на Riverpod 2.x

## Зачем мигрировать?

Текущая реализация использует базовые `FutureProvider`, которые:
- ❌ Пересоздаются при каждом rebuild
- ❌ Не кэшируют данные эффективно
- ❌ Сложно обновлять императивно
- ❌ Нет централизованного управления состоянием

### Преимущества Riverpod 2.x:
- ✅ Автоматическое кэширование и инвалидация
- ✅ Реактивное обновление UI
- ✅ Типобезопасность на уровне компилятора
- ✅ Легкое тестирование (mockable providers)
- ✅ DevTools интеграция

---

## Архитектура

```
UI Layer (Screens/Widgets)
    ↓ watch/read
Provider Layer (Notifiers)
    ↓ use
Service Layer (AuthService, ChatService)
    ↓ call
Data Layer (Matrix API, Local DB)
```

### Типы Provider'ов

| Тип | Когда использовать | Пример |
|-----|-------------------|--------|
| `Provider` | Неизменяемые значения | Config, constants |
| `StateProvider` | Простое состояние | Theme toggle, counters |
| `StateNotifierProvider` | Сложное состояние | Auth state, chat list |
| `FutureProvider` | Async данные без изменений | API fetch once |
| `StreamProvider` | Realtime данные | WebSocket, Firebase |
| `AsyncNotifierProvider` | Async с возможностью обновления | Auth, User profile |

---

## Миграция пошагово

### Шаг 1: Обновление зависимостей

```yaml
# pubspec.yaml
dependencies:
  flutter_riverpod: ^2.5.1
  riverpod_annotation: ^2.3.5

dev_dependencies:
  riverpod_generator: ^2.4.0
  build_runner: ^2.4.9
  riverpod_lint: ^2.3.10
```

```bash
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```

### Шаг 2: Обновление main.dart

**До:**
```dart
void main() {
  runApp(const TwoSpaceApp());
}
```

**После:**
```dart
void main() {
  runApp(
    ProviderScope(
      child: const TwoSpaceApp(),
    ),
  );
}
```

### Шаг 3: Миграция AuthProvider

**Старая версия (lib/providers/auth_provider.dart):**
```dart
final currentUserProvider = FutureProvider<String?>((ref) async {
  final auth = AuthService();
  return auth.getCurrentUserId();
});
```

**Проблемы:**
- Пересоздаёт AuthService при каждом вызове
- Нет возможности обновить состояние после login/logout
- Нет кэширования

**Новая версия (lib/providers/auth_notifier.dart):**
```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../services/auth_service.dart';

part 'auth_notifier.g.dart';

@riverpod
class AuthNotifier extends _$AuthNotifier {
  // Singleton AuthService
  late final AuthService _authService;

  @override
  Future<AuthState> build() async {
    _authService = ref.read(authServiceProvider);
    return _loadAuthState();
  }

  Future<AuthState> _loadAuthState() async {
    try {
      final token = await _authService.getMatrixTokenForUser();
      final userId = await _authService.getCurrentUserId();
      
      if (token != null && userId != null) {
        return AuthState.authenticated(userId: userId, token: token);
      }
      return const AuthState.unauthenticated();
    } catch (e) {
      return AuthState.error(message: e.toString());
    }
  }

  // Методы для изменения состояния
  Future<void> login(String username, String password) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _authService.login(username, password);
      return _loadAuthState();
    });
  }

  Future<void> logout() async {
    state = const AsyncValue.loading();
    await _authService.logout();
    state = const AsyncValue.data(AuthState.unauthenticated());
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_loadAuthState);
  }
}

// AuthState model
class AuthState {
  final String? userId;
  final String? token;
  final bool isAuthenticated;
  final String? errorMessage;

  const AuthState.authenticated({
    required this.userId,
    required this.token,
  })  : isAuthenticated = true,
        errorMessage = null;

  const AuthState.unauthenticated()
      : userId = null,
        token = null,
        isAuthenticated = false,
        errorMessage = null;

  const AuthState.error({required String message})
      : userId = null,
        token = null,
        isAuthenticated = false,
        errorMessage = message;
}

// AuthService как provider для DI
@riverpod
AuthService authService(AuthServiceRef ref) {
  return AuthService();
}
```

**Генерация кода:**
```bash
flutter pub run build_runner watch
```

### Шаг 4: Использование в UI

**Старый способ:**
```dart
class LoginScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AuthService().isAuthenticated(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return CircularProgressIndicator();
        // ...
      },
    );
  }
}
```

**Новый способ:**
```dart
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    
    return authState.when(
      data: (state) {
        if (state.isAuthenticated) {
          // Redirect to home
          return HomeScreen();
        }
        return _buildLoginForm(ref);
      },
      loading: () => const CircularProgressIndicator(),
      error: (error, stack) => Text('Ошибка: $error'),
    );
  }

  Widget _buildLoginForm(WidgetRef ref) {
    return ElevatedButton(
      onPressed: () async {
        final notifier = ref.read(authNotifierProvider.notifier);
        await notifier.login(username, password);
      },
      child: const Text('Войти'),
    );
  }
}
```

### Шаг 5: Миграция других сервисов

**ChatProvider:**
```dart
@riverpod
class ChatList extends _$ChatList {
  @override
  Future<List<Chat>> build() async {
    final chatService = ref.read(chatServiceProvider);
    return chatService.getJoinedChats();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final chatService = ref.read(chatServiceProvider);
      return chatService.getJoinedChats();
    });
  }

  Future<void> createChat(String userId) async {
    final chatService = ref.read(chatServiceProvider);
    await chatService.createDirectChat(userId);
    await refresh();
  }
}
```

---

## Best Practices

### 1. Избегайте создания сервисов в provider'ах

❌ **Плохо:**
```dart
final userProvider = FutureProvider((ref) async {
  final service = UserService(); // Новый instance каждый раз!
  return service.getUser();
});
```

✅ **Хорошо:**
```dart
@riverpod
UserService userService(UserServiceRef ref) => UserService();

@riverpod
Future<User> user(UserRef ref) async {
  final service = ref.watch(userServiceProvider);
  return service.getUser();
}
```

### 2. Используйте family для параметризованных provider'ов

```dart
@riverpod
Future<Chat> chat(ChatRef ref, String chatId) async {
  final service = ref.watch(chatServiceProvider);
  return service.getChatById(chatId);
}

// Использование:
final chat = ref.watch(chatProvider('!room123'));
```

### 3. Инвалидация при изменениях

```dart
Future<void> sendMessage(String chatId, String text) async {
  await chatService.sendMessage(chatId, text);
  
  // Обновить конкретный чат
  ref.invalidate(chatProvider(chatId));
  
  // Или обновить весь список
  ref.invalidate(chatListProvider);
}
```

### 4. Обработка ошибок

```dart
final userData = ref.watch(userProvider);

userData.when(
  data: (user) => Text(user.name),
  loading: () => const CircularProgressIndicator(),
  error: (err, stack) => ErrorWidget(error: err),
);

// Или для выборочной обработки:
if (userData.hasError) {
  return ErrorWidget(error: userData.error!);
}
```

---

## Тестирование

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:mockito/mockito.dart';

class MockAuthService extends Mock implements AuthService {}

void main() {
  test('AuthNotifier should load authenticated state', () async {
    final mockAuth = MockAuthService();
    when(mockAuth.getMatrixTokenForUser()).thenAnswer((_) async => 'token123');
    when(mockAuth.getCurrentUserId()).thenAnswer((_) async => '@user:matrix.org');

    final container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(mockAuth),
      ],
    );

    final state = await container.read(authNotifierProvider.future);
    
    expect(state.isAuthenticated, true);
    expect(state.userId, '@user:matrix.org');
  });
}
```

---

## Чеклист миграции

- [ ] Обновить dependencies в pubspec.yaml
- [ ] Обернуть app в ProviderScope
- [ ] Создать auth_notifier.dart с AsyncNotifierProvider
- [ ] Мигрировать LoginScreen на ConsumerWidget
- [ ] Создать chat_notifier.dart
- [ ] Мигрировать HomeScreen на ConsumerWidget
- [ ] Добавить unit-тесты для notifiers
- [ ] Обновить документацию
- [ ] Code review и merge PR

---

## Полезные ссылки

- [Riverpod Docs](https://riverpod.dev)
- [Code Generator](https://riverpod.dev/docs/concepts/about_code_generation)
- [Migration Guide](https://riverpod.dev/docs/migration/from_state_notifier)
- [DevTools](https://riverpod.dev/docs/cookbooks/testing)

---

**Вопросы?** Создайте issue или спросите в Telegram-канале проекта!
