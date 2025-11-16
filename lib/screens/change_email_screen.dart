import 'package:flutter/material.dart';
import 'package:two_space_app/services/matrix_service.dart';
import 'package:two_space_app/services/settings_service.dart';

class ChangeEmailScreen extends StatefulWidget {
  const ChangeEmailScreen({super.key});

  @override
  State<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends State<ChangeEmailScreen> {
  final _emailCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  bool _loading = false;
  String? _currentEmail;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    try {
      final acct = await AppwriteService.getAccount();
      if (!mounted) return;
      final email = (acct['email'] as String?) ?? '';
      setState(() => _currentEmail = email.isNotEmpty ? email : null);
    } catch (_) {}
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pwd = _pwdCtrl.text.trim();
    if (email.isEmpty) return;
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    final navState = Navigator.of(context);
    try {
      await AppwriteService.updateEmail(email: email, password: pwd.isEmpty ? null : pwd);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Email изменён. Проверьте почту для подтверждения, если требуется.')));
      navState.pop(true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Не удалось изменить email: ${AppwriteService.readableError(e)}')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Изменить email')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ValueListenableBuilder<bool>(
          valueListenable: SettingsService.paleVioletNotifier,
          builder: (c, pale, _) {
            final theme = Theme.of(context).copyWith(
              inputDecorationTheme: InputDecorationTheme(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: pale,
                fillColor: pale ? const Color(0xFFF6F0FF) : null,
              ),
            );
            return Theme(
              data: theme,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Введите новый email и, если требуется, текущий пароль для подтверждения.'),
                  if (_currentEmail != null) ...[
                    const SizedBox(height: 8),
                    Text('Текущий: ', style: Theme.of(context).textTheme.bodySmall),
                    Text(_currentEmail ?? '', style: Theme.of(context).textTheme.bodyMedium),
                  ],
                  const SizedBox(height: 12),
                  TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Новый email')),
                  const SizedBox(height: 12),
                  TextField(controller: _pwdCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Текущий пароль')),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Изменить email'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
