import 'package:flutter/material.dart';
import 'package:two_space_app/services/appwrite_service.dart';
import 'package:two_space_app/services/settings_service.dart';

class ChangePhoneScreen extends StatefulWidget {
  const ChangePhoneScreen({super.key});

  @override
  State<ChangePhoneScreen> createState() => _ChangePhoneScreenState();
}

class _ChangePhoneScreenState extends State<ChangePhoneScreen> {
  final _phoneCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  bool _loading = false;
  String? _currentPhone;

  @override
  void initState() {
    super.initState();
    _loadCurrentPhone();
  }

  Future<void> _loadCurrentPhone() async {
    try {
      final acct = await AppwriteService.getAccount();
      if (!mounted) return;
      String phoneVal = '';
      try {
        final acctPhone = acct['phone'];
        if (acctPhone is String) {
          phoneVal = acctPhone;
        } else if (acctPhone is Map) {
          phoneVal = (acctPhone['phone'] ?? acctPhone['number'] ?? acctPhone['value'])?.toString() ?? '';
        }
      } catch (_) {}
      if (phoneVal.isEmpty) phoneVal = ((acct['prefs'] is Map) ? (acct['prefs']['phone'] as String? ?? '') : '');
      setState(() => _currentPhone = phoneVal.isNotEmpty ? phoneVal : null);
    } catch (_) {}
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = _phoneCtrl.text.trim();
    final pwd = _pwdCtrl.text.trim();
    if (phone.isEmpty) return;
    setState(() => _loading = true);
    try {
      await AppwriteService.updatePhone(phone: phone, password: pwd.isEmpty ? null : pwd);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Номер телефона изменён')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось изменить номер: ${AppwriteService.readableError(e)}')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Изменить номер телефона')),
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
                  const Text('Введите новый номер телефона и текущий пароль.'),
                  if (_currentPhone != null) ...[
                    const SizedBox(height: 8),
                    Text('Текущий: ', style: Theme.of(context).textTheme.bodySmall),
                    Text(_currentPhone ?? '', style: Theme.of(context).textTheme.bodyMedium),
                  ],
                  const SizedBox(height: 12),
                  TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Новый номер (+7...)')),
                  const SizedBox(height: 12),
                  TextField(controller: _pwdCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Текущий пароль (если требуется)')),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Изменить номер'),
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
