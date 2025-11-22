import 'package:flutter/material.dart';
import 'package:two_space_app/screens/change_email_screen.dart';
import 'package:two_space_app/screens/change_phone_screen.dart';
import 'package:two_space_app/services/settings_service.dart';
import 'package:two_space_app/screens/tfa_setup_screen.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  bool _hideFromSearch = false;
  bool _hideLastSeen = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadPref();
  }

  Future<void> _loadPref() async {
    try {
      // AppwriteService not available, skip loading prefs
      if (mounted) setState(() {
        _hideFromSearch = false;
        _hideLastSeen = false;
      });
    } catch (_) {}
  }

  Future<void> _toggle(bool v) async {
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // AppwriteService not available, skip server update
      if (!mounted) return;
      setState(() => _hideFromSearch = v);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Не удалось обновить приватность: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleLastSeen(bool v) async {
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // AppwriteService not available, skip server update
      if (!mounted) return;
      setState(() => _hideLastSeen = v);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Не удалось обновить настройку: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Приватность')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        SwitchListTile(title: const Text('Скрыть из поиска'), subtitle: const Text('Не показывать меня в результатах поиска по номеру или никнейму'), value: _hideFromSearch, onChanged: _loading ? null : _toggle),
        const SizedBox(height: 6),
        SwitchListTile(title: const Text('Скрывать статус "был(а) в сети"'), subtitle: const Text('Не показывать время последнего захода в приложение'), value: _hideLastSeen, onChanged: _loading ? null : _toggleLastSeen),
        const SizedBox(height: 12),
        // Session persistence setting (silent re-login)
        ValueListenableBuilder<int>(
          valueListenable: SettingsService.sessionTimeoutDaysNotifier,
          builder: (c, days, _) {
            return Column(children: [
              Material(
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: ListTile(
                  leading: const Icon(Icons.lock_clock),
                  title: const Text('Срок действия входа'),
                  subtitle: Text('Автоматический повторный вход на этом устройстве: $days дней'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _loading
                      ? null
                      : () async {
                          final controller = TextEditingController(text: days.toString());
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Срок действия входа (дни)'),
                              content: Column(mainAxisSize: MainAxisSize.min, children: [
                                const Text('Выберите количество дней (мин: 7, макс: 365).'),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: controller,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(labelText: 'Дней'),
                                ),
                              ]),
                              actions: [
                                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
                                TextButton(
                                    onPressed: () {
                                      final v = int.tryParse(controller.text.trim()) ?? -1;
                                      if (v < 7 || v > 365) {
                                        // show inline error
                                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Введите число от 7 до 365')));
                                        return;
                                      }
                                      Navigator.of(ctx).pop(true);
                                    },
                                    child: const Text('Сохранить')),
                              ],
                            ),
                          );
                            if (ok == true) {
                              final v = int.tryParse(controller.text.trim()) ?? days;
                              final newV = v.clamp(7, 365);
                              final messenger = ScaffoldMessenger.of(context);
                              await SettingsService.setSessionTimeoutDays(newV);
                              messenger.showSnackBar(SnackBar(content: Text('Срок входа установлен: $newV дней')));
                            }
                        },
                ),
              ),
              const SizedBox(height: 12),
            ]);
          },
        ),
        Material(
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            leading: const Icon(Icons.email),
            title: const Text('Изменить email'),
            subtitle: const Text('Безопасно поменяйте адрес электронной почты и подтвердите его'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangeEmailScreen()));
            },
          ),
        ),
        const SizedBox(height: 8),
        Material(
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            leading: const Icon(Icons.security),
            title: const Text('Двухфакторная аутентификация (2FA)'),
            subtitle: const Text('Включить/отключить 2FA через приложение аутентификатора'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              // Navigate to TFA setup screen
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TfaSetupScreen()));
            },
          ),
        ),
        const SizedBox(height: 8),
        Material(
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            leading: const Icon(Icons.phone),
            title: const Text('Изменить телефон'),
            subtitle: const Text('Безопасно поменяйте номер телефона и подтвердите его'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePhoneScreen()));
            },
          ),
        ),
      ]),
    );
  }
}

