import 'package:flutter/material.dart';
import 'package:two_space_app/services/dev_logger.dart';
import 'package:two_space_app/services/update_service.dart';
import 'package:two_space_app/services/settings_service.dart';
import 'package:two_space_app/screens/login_screen.dart';
import 'package:two_space_app/screens/register_screen.dart';
import 'package:two_space_app/screens/account_settings_screen.dart';
import 'package:two_space_app/screens/home_screen.dart';
import 'package:two_space_app/screens/customization_screen.dart';
import 'package:two_space_app/screens/privacy_screen.dart';
// Chat screen import removed from dev menu (not used currently)
import 'package:two_space_app/services/appwrite_service.dart';
import 'package:two_space_app/services/navigation_service.dart';

class DevMenuScreen extends StatefulWidget {
  const DevMenuScreen({super.key});

  @override
  State<DevMenuScreen> createState() => _DevMenuScreenState();
}

class _DevMenuScreenState extends State<DevMenuScreen> {
  late final Stream<List<String>> _logStream;

  @override
  void initState() {
    super.initState();
    _logStream = DevLogger.stream;
    DevLogger.log('Opened Dev Menu');
  }

  @override
  Widget build(BuildContext context) {
    final routes = <Map<String, dynamic>>[
      {'label': 'Home', 'action': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HomeScreen()))},
      {'label': 'Login', 'action': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()))},
      {'label': 'Register', 'action': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen()))},
      {'label': 'Settings', 'action': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountSettingsScreen()))},
      {'label': 'Customization', 'action': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomizationScreen()))},
      {'label': 'Privacy', 'action': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyScreen()))},
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Developer Menu'), actions: [IconButton(icon: const Icon(Icons.clear_all), onPressed: () { DevLogger.clear(); setState(() {}); })]),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: routes.map((r) {
                return ElevatedButton(child: Text(r['label'] ?? ''), onPressed: () { DevLogger.log('Navigate: ${r['label']}'); try { (r['action'] as void Function())(); } catch (e) { DevLogger.log('Navigation failed: $e'); } });
              }).toList(),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    DevLogger.log('Check for updates (dev menu)');
                    try {
                      final info = await UpdateService.checkForUpdate();
                      DevLogger.log('Update check: ${info != null}');
                      if (!mounted) return;
                      final navCtx = appNavigatorKey.currentContext;
                      if (navCtx != null) ScaffoldMessenger.of(navCtx).showSnackBar(const SnackBar(content: Text('Update check finished (см. логи)')));
                    } catch (e) {
                      DevLogger.log('Update check failed: $e');
                      if (!mounted) return;
                      final navCtx = appNavigatorKey.currentContext;
                      if (navCtx != null) ScaffoldMessenger.of(navCtx).showSnackBar(SnackBar(content: Text('Ошибка проверки: $e')));
                    }
                  },
                  icon: const Icon(Icons.system_update),
                  label: const Text('Check updates'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    DevLogger.log('Clear settings cache');
                    await SettingsService.clearCachedProfile();
                    if (!mounted) return;
                    final navCtx = appNavigatorKey.currentContext;
                    if (navCtx != null) ScaffoldMessenger.of(navCtx).showSnackBar(const SnackBar(content: Text('Cached profile cleared')));
                  },
                  icon: const Icon(Icons.delete),
                  label: const Text('Clear profile cache'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    DevLogger.log('Clear JWT & session');
                    try {
                      await AppwriteService.clearJwt();
                      await AppwriteService.deleteCurrentSession();
                      if (!mounted) return;
                      final navCtx = appNavigatorKey.currentContext;
                      if (navCtx != null) ScaffoldMessenger.of(navCtx).showSnackBar(const SnackBar(content: Text('Cleared session')));
                    } catch (e) {
                      DevLogger.log('Clear session failed: $e');
                      if (!mounted) return;
                      final navCtx = appNavigatorKey.currentContext;
                      if (navCtx != null) ScaffoldMessenger.of(navCtx).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Clear session'),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(child: StreamBuilder<List<String>>(stream: _logStream, initialData: DevLogger.all, builder: (context, snap) {
            final logs = snap.data ?? [];
            return ListView.builder(itemCount: logs.length, itemBuilder: (c, i) => Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Text(logs[i], style: const TextStyle(fontFamily: 'monospace', fontSize: 12))));
          })),
        ]),
      ),
    );
  }
}
