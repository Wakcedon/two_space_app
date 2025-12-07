import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:two_space_app/services/dev_logger.dart';
import 'package:two_space_app/services/update_service.dart';
import 'package:two_space_app/services/settings_service.dart';
import 'package:two_space_app/screens/login_screen.dart';
import 'package:two_space_app/screens/register_screen.dart';
import 'package:two_space_app/screens/home_screen.dart';
import 'package:two_space_app/screens/customization_screen.dart';
import 'package:two_space_app/screens/privacy_screen.dart';
import 'package:two_space_app/services/navigation_service.dart';

class DevMenuScreen extends StatefulWidget {
  const DevMenuScreen({super.key});

  @override
  State<DevMenuScreen> createState() => _DevMenuScreenState();
}

class _DevMenuScreenState extends State<DevMenuScreen> {
  late final Stream<List<String>> _logStream;
  late final DevLogger _logger = DevLogger('DevMenu');
  int _autoScrollLines = 50;
  bool _colorize = true;

  @override
  void initState() {
    super.initState();
    _logStream = DevLogger.stream;
    _logger.info('═══════════════════════════════════════════════════════');
    _logger.info('🚀 DEVELOPER MENU OPENED');
    _logger.info('═══════════════════════════════════════════════════════');
  }

  Color _getLogColor(String log) {
    if (!_colorize) return Colors.white;
    if (log.contains('[ERROR]')) return const Color(0xFFEF5350);
    if (log.contains('[WARN]')) return const Color(0xFFFFA726);
    if (log.contains('[INFO]')) return const Color(0xFF29B6F6);
    if (log.contains('[DEBUG]')) return Colors.grey[400] ?? Colors.white;
    if (log.contains('[HTTP]')) return const Color(0xFF66BB6A);
    if (log.contains('API Response') || log.contains('Response:')) return const Color(0xFFAB47BC);
    return Colors.white;
  }

  String _truncateLog(String log, {int maxLength = 500}) {
    if (log.length <= maxLength) return log;
    return '${log.substring(0, maxLength)}...';
  }

  void _copyLog(String log) {
    Clipboard.setData(ClipboardData(text: log));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✓ Лог скопирован в буфер обмена'), duration: Duration(seconds: 1)),
    );
  }

  void _copyAllLogs() {
    final allLogs = DevLogger.all.join('\n');
    Clipboard.setData(ClipboardData(text: allLogs));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✓ ${DevLogger.all.length} логов скопировано'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _exportLogs() {
    final timestamp = DateTime.now().toIso8601String();
    final header = '''
═══════════════════════════════════════════════════════════════════
🔍 DEBUG LOG EXPORT - TwoSpace
Время: $timestamp
Количество логов: ${DevLogger.all.length}
═══════════════════════════════════════════════════════════════════
''';
    final allLogs = header + DevLogger.all.join('\n');
    Clipboard.setData(ClipboardData(text: allLogs));
    _logger.info('✓ Экспортировано ${DevLogger.all.length} логов');
  }

  @override
  Widget build(BuildContext context) {
    final routes = <Map<String, dynamic>>[
      {
        'label': 'Home',
        'action': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HomeScreen())),
      },
      {
        'label': 'Login',
        'action': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
      },
      {
        'label': 'Register',
        'action': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
      },
      {
        'label': 'Customization',
        'action': () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomizationScreen())),
      },
      {
        'label': 'Privacy',
        'action': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyScreen())),
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('🔧 Developer Menu'),
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить логи',
            onPressed: () => setState(() {}),
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Копировать все',
            onPressed: _copyAllLogs,
          ),
          IconButton(
            icon: const Icon(Icons.cloud_download),
            tooltip: 'Экспортировать',
            onPressed: _exportLogs,
          ),
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: 'Очистить логи',
            onPressed: () {
              DevLogger.clear();
              _logger.info('🗑️ Логи очищены');
              setState(() {});
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Navigation buttons
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Навигация',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: routes.map((r) {
                      return ElevatedButton(
                        onPressed: () {
                          _logger.info('▶️ Navigate: ${r['label']}');
                          try {
                            (r['action'] as void Function())();
                          } catch (e) {
                            _logger.error('Navigation failed: $e');
                          }
                        },
                        child: Text(r['label'] ?? ''),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const Divider(),

            // Debug actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Действия',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          _logger.info('📡 Проверка обновлений...');
                          try {
                            final info = await UpdateService.checkForUpdate();
                            _logger.info('✓ Обновления: ${info != null ? 'Найдены' : 'Нет'}');
                            if (!mounted) return;
                            final navCtx = appNavigatorKey.currentContext;
                            if (navCtx != null) {
                              ScaffoldMessenger.of(navCtx).showSnackBar(
                                const SnackBar(content: Text('✓ Проверка завершена (см. логи)')),
                              );
                            }
                          } catch (e) {
                            _logger.error('Проверка обновлений: $e');
                            if (!mounted) return;
                            final navCtx = appNavigatorKey.currentContext;
                            if (navCtx != null) {
                              ScaffoldMessenger.of(navCtx)
                                  .showSnackBar(SnackBar(content: Text('❌ Ошибка: $e')));
                            }
                          }
                        },
                        icon: const Icon(Icons.system_update),
                        label: const Text('Проверить обновления'),
                      ),
                      ElevatedButton.icon(
                        onPressed: () async {
                          _logger.debug('🗂️ Очистка кеша профиля');
                          await SettingsService.clearCachedProfile();
                          _logger.info('✓ Кеш профиля очищен');
                          if (!mounted) return;
                          final navCtx = appNavigatorKey.currentContext;
                          if (navCtx != null) {
                            ScaffoldMessenger.of(navCtx).showSnackBar(
                              const SnackBar(content: Text('✓ Кеш очищен')),
                            );
                          }
                        },
                        icon: const Icon(Icons.delete),
                        label: const Text('Очистить кеш'),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          _logger.debug('📋 Тест логирования');
                          _logger.info('ℹ️ Информационное сообщение');
                          _logger.warning('⚠️ Предупреждение');
                          _logger.error('❌ Ошибка');
                          _logger.debug('🔍 Отладочная информация');
                          _logger.info('🌐 [HTTP] GET /api/v1/user - Response: 200');
                        },
                        icon: const Icon(Icons.bug_report),
                        label: const Text('Тест логов'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(),

            // Settings
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: _colorize,
                        onChanged: (v) {
                          setState(() => _colorize = v ?? true);
                          _logger.debug(_colorize ? '🎨 Цветизация: ВКЛ' : '⚫ Цветизация: ВЫКЛ');
                        },
                      ),
                      const Text('Цветизация логов'),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('Строк: '),
                      DropdownButton<int>(
                        value: _autoScrollLines,
                        items: [10, 25, 50, 100, 200].map((v) {
                          return DropdownMenuItem(value: v, child: Text(v.toString()));
                        }).toList(),
                        onChanged: (v) => setState(() => _autoScrollLines = v ?? 50),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(),

            // Logs viewer
            Expanded(
              child: StreamBuilder<List<String>>(
                stream: _logStream,
                initialData: DevLogger.all,
                builder: (context, snap) {
                  final logs = snap.data ?? [];
                  final displayLogs = logs.length > _autoScrollLines
                      ? logs.sublist(logs.length - _autoScrollLines)
                      : logs;

                  return logs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.history, size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              Text(
                                'Логи пусты',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: displayLogs.length,
                          reverse: false,
                          itemBuilder: (c, i) {
                            final log = displayLogs[i];
                            final isError = log.contains('[ERROR]');
                            final isWarn = log.contains('[WARN]');

                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              child: GestureDetector(
                                onLongPress: () {
                                  showModalBottomSheet(
                                    context: context,
                                    builder: (ctx) => Container(
                                      color: Theme.of(context).colorScheme.surface,
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'Опции логи',
                                            style: Theme.of(context).textTheme.titleMedium,
                                          ),
                                          const SizedBox(height: 16),
                                          ListTile(
                                            leading: const Icon(Icons.copy),
                                            title: const Text('Копировать'),
                                            onTap: () {
                                              _copyLog(log);
                                              Navigator.pop(ctx);
                                            },
                                          ),
                                          ListTile(
                                            leading: const Icon(Icons.search),
                                            title: const Text('Найти похожие'),
                                            onTap: () {
                                              final keyword = log.split(':').first;
                                              _logger.info('Поиск: $keyword');
                                              Navigator.pop(ctx);
                                            },
                                          ),
                                          ListTile(
                                            leading: const Icon(Icons.delete),
                                            title: const Text('Удалить эту строку'),
                                            onTap: () {
                                              DevLogger.all.remove(log);
                                              setState(() {});
                                              Navigator.pop(ctx);
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isError
                                        ? Colors.red.withValues(alpha: 0.1)
                                        : isWarn
                                            ? Colors.orange.withValues(alpha: 0.1)
                                            : null,
                                    border: Border(
                                      left: BorderSide(
                                        color: _getLogColor(log),
                                        width: 3,
                                      ),
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  child: SelectableText(
                                    _truncateLog(log),
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: _getLogColor(log),
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
