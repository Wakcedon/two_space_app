# 🚀 Руководство по миграции на Riverpod 2.5

## 🎯 Цели миграции

Переход от `setState` и `ValueNotifier` к Riverpod даёт:

- ✅ **Лучшая тестируемость** - providers легко мокать
- ✅ **Автоматическое кэширование** - данные не перезагружаются без необходимости
- ✅ **Compile-time safety** - ошибки находятся до запуска
- ✅ **Упрощение кода** - меньше boilerplate
- ✅ **Reactive UI** - UI автоматически обновляется при изменении состояния

---

## 📚 Типы Provider'ов в Riverpod

| Тип | Когда использовать | Пример |
|------|-------------|--------|
| **Provider** | Неизменяемые значения (конфиг, сервисы) | `final configProvider = Provider((ref) => AppConfig());` |
| **StateProvider** | Простое изменяемое состояние | `final counterProvider = StateProvider((ref) => 0);` |
| **FutureProvider** | Async данные (загрузка из API) | `final userProvider = FutureProvider((ref) async => fetchUser());` |
| **StreamProvider** | Realtime данные (WebSocket, Firebase) | `final messagesProvider = StreamProvider((ref) => messageStream);` |
| **NotifierProvider** | Сложная логика с методами | `final authProvider = NotifierProvider<AuthNotifier, AuthState>(() => AuthNotifier());` |
| **AsyncNotifierProvider** | Async логика с методами | `final chatProvider = AsyncNotifierProvider<ChatNotifier, List<Chat>>(() => ChatNotifier());` |

---

## 🛠️ Пошаговая миграция: SettingsService → SettingsProvider

### Шаг 1: Старый код (до миграции)

```dart
// lib/services/settings_service.dart
class SettingsService {
  static final ValueNotifier<ThemeSettings> themeNotifier = 
    ValueNotifier(ThemeSettings());

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final primaryColor = prefs.getInt('primaryColor') ?? 0xFF6A1B9A;
    themeNotifier.value = ThemeSettings(primaryColorValue: primaryColor);
  }

  static Future<void> savePrimaryColor(int color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('primaryColor', color);
    themeNotifier.value = themeNotifier.value.copyWith(primaryColorValue: color);
  }
}

// Использование в UI:
ValueListenableBuilder<ThemeSettings>(
  valueListenable: SettingsService.themeNotifier,
  builder: (context, settings, _) {
    return Container(color: Color(settings.primaryColorValue));
  },
)
```

### Шаг 2: Создаём Notifier

```dart
// lib/providers/settings_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 1. Определяем модель состояния
class ThemeSettings {
  final int primaryColorValue;
  final String fontFamily;
  final int fontWeight;

  ThemeSettings({
    this.primaryColorValue = 0xFF6A1B9A,
    this.fontFamily = 'Roboto',
    this.fontWeight = 400,
  });

  ThemeSettings copyWith({
    int? primaryColorValue,
    String? fontFamily,
    int? fontWeight,
  }) {
    return ThemeSettings(
      primaryColorValue: primaryColorValue ?? this.primaryColorValue,
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
    );
  }
}

// 2. Создаём Notifier с бизнес-логикой
class SettingsNotifier extends Notifier<ThemeSettings> {
  @override
  ThemeSettings build() {
    // Инициализация: загружаем сохранённые настройки
    _loadSettings();
    return ThemeSettings(); // Дефолтное значение
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = ThemeSettings(
        primaryColorValue: prefs.getInt('primaryColor') ?? 0xFF6A1B9A,
        fontFamily: prefs.getString('fontFamily') ?? 'Roboto',
        fontWeight: prefs.getInt('fontWeight') ?? 400,
      );
    } catch (e) {
      // Логируем ошибку, но не крашим приложение
      print('Failed to load settings: $e');
    }
  }

  Future<void> updatePrimaryColor(int color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('primaryColor', color);
    state = state.copyWith(primaryColorValue: color);
  }

  Future<void> updateFontFamily(String family) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fontFamily', family);
    state = state.copyWith(fontFamily: family);
  }
}

// 3. Создаём Provider
final settingsProvider = NotifierProvider<SettingsNotifier, ThemeSettings>(
  () => SettingsNotifier(),
);
```

### Шаг 3: Обновляем UI

```dart
// Было:
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeSettings>(
      valueListenable: SettingsService.themeNotifier,
      builder: (context, settings, _) {
        return MaterialApp(/* ... */);
      },
    );
  }
}

// Стало:
class MyApp extends ConsumerWidget {  // ← Изменили StatelessWidget на ConsumerWidget
  @override
  Widget build(BuildContext context, WidgetRef ref) {  // ← Добавили WidgetRef
    final settings = ref.watch(settingsProvider);  // ← Читаем состояние

    return MaterialApp(
      theme: ThemeData(
        primaryColor: Color(settings.primaryColorValue),
        fontFamily: settings.fontFamily,
      ),
      home: HomeScreen(),
    );
  }
}
```

### Шаг 4: Обновляем main.dart

```dart
// Было:
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.load();
  runApp(MyApp());
}

// Стало:
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(  // ← Оборачиваем в ProviderScope
      child: MyApp(),
    ),
  );
}
```

### Шаг 5: Использование в экранах

```dart
// Чтение значения:
class SettingsScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    
    return Text('Current color: ${settings.primaryColorValue}');
  }
}

// Изменение значения:
class ColorPickerButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () {
        ref.read(settingsProvider.notifier).updatePrimaryColor(0xFF00FF00);
      },
      child: Text('Change Color'),
    );
  }
}
```

---

## 🧪 Тестирование Provider'ов

```dart
// test/providers/settings_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SettingsNotifier', () {
    late ProviderContainer container;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state has default values', () {
      final settings = container.read(settingsProvider);
      expect(settings.primaryColorValue, 0xFF6A1B9A);
    });

    test('updatePrimaryColor changes state', () async {
      final notifier = container.read(settingsProvider.notifier);
      await notifier.updatePrimaryColor(0xFF0000FF);

      final settings = container.read(settingsProvider);
      expect(settings.primaryColorValue, 0xFF0000FF);
    });
  });
}
```

---

## ⚖️ Когда использовать `ref.watch` vs `ref.read`

| Метод | Когда использовать | Пример |
|--------|-------------|--------|
| **ref.watch** | В `build()` для reactive UI | `final settings = ref.watch(settingsProvider);` |
| **ref.read** | В event handlers (кнопки, callbacks) | `ref.read(settingsProvider.notifier).update();` |
| **ref.listen** | Для side effects (навигация, snackbars) | `ref.listen(authProvider, (prev, next) => navigate());` |

⚠️ **Не используйте `ref.read` в `build()`** - UI не обновится!

---

## 🚨 Частые ошибки

### 1. Использование StatefulWidget вместо ConsumerWidget

❌ **Неправильно:**
```dart
class MyScreen extends StatefulWidget {
  // Не может использовать ref!
}
```

✅ **Правильно:**
```dart
class MyScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends ConsumerState<MyScreen> {
  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    return Text('$data');
  }
}
```

### 2. Забыли ProviderScope

❌ **Неправильно:**
```dart
void main() {
  runApp(MyApp()); // Крэш при попытке использовать ref!
}
```

✅ **Правильно:**
```dart
void main() {
  runApp(ProviderScope(child: MyApp()));
}
```

### 3. Мутация state напрямую

❌ **Неправильно:**
```dart
state.primaryColor = 0xFF0000FF; // Не сработает!
```

✅ **Правильно:**
```dart
state = state.copyWith(primaryColorValue: 0xFF0000FF);
```

---

## 📅 План миграции TwoSpace

### Неделя 1: Простые сервисы
- [x] SettingsService → SettingsProvider
- [ ] ThemeService (paleVioletNotifier) → ThemeProvider
- [ ] DebugService → DebugProvider

### Неделя 2: Аутентификация
- [ ] AuthService → AsyncNotifierProvider (async login/logout)
- [ ] MatrixService → интегрировать с AuthProvider

### Неделя 3: Чаты и сообщения
- [ ] ChatService → StreamProvider (реалтайм сообщения)
- [ ] RealtimeService → StreamProvider

### Неделя 4: UI компоненты
- [ ] Обновить все StatelessWidget → ConsumerWidget
- [ ] Удалить ValueListenableBuilder

---

## 🔧 Troubleshooting

### Provider not found

**Ошибка:** `ProviderNotFoundException`

**Решение:** Убедитесь что `ProviderScope` оборачивает всё приложение в `main()`.

### UI не обновляется

**Проблема:** Используете `ref.read` в `build()`

**Решение:** Замените на `ref.watch`.

### Tests failing

**Проблема:** Providers не доступны в тестах

**Решение:** Создайте `ProviderContainer` в `setUp()`:

```dart
late ProviderContainer container;

setUp(() {
  container = ProviderContainer(
    overrides: [
      // Mock providers here
    ],
  );
});

tearDown(() {
  container.dispose();
});
```

---

## 📚 Дополнительные ресурсы

- [Riverpod официальная документация](https://riverpod.dev)
- [Code With Andrea - Riverpod Guide](https://codewithandrea.com/articles/flutter-state-management-riverpod/)
- [Riverpod GitHub Examples](https://github.com/rrousselGit/riverpod/tree/master/examples)

---

🎉 **Happy Coding!**