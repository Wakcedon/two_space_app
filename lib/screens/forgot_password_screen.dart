import 'package:flutter/material.dart';
import 'package:two_space_app/services/appwrite_service.dart';
import 'package:two_space_app/services/navigation_service.dart';
// ui_tokens not needed here

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      final navCtx = appNavigatorKey.currentContext;
      if (navCtx != null) ScaffoldMessenger.of(navCtx).showSnackBar(const SnackBar(content: Text('Введите email')));
      return;
    }
    setState(() => _loading = true);
    try {
      await AppwriteService.createPasswordRecovery(email);
  if (!mounted) return;
  final navCtx = appNavigatorKey.currentContext;
  if (navCtx != null) ScaffoldMessenger.of(navCtx).showSnackBar(const SnackBar(content: Text('Письмо с инструкциями отправлено. Проверьте почту.')));
  appNavigatorKey.currentState?.pop();
    } catch (e) {
  if (!mounted) return;
  final navCtx = appNavigatorKey.currentContext;
  if (navCtx != null) ScaffoldMessenger.of(navCtx).showSnackBar(SnackBar(content: Text('Ошибка: ${AppwriteService.readableError(e)}')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Восстановление пароля')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 8),
          Text('Введите email, на который будет отправлена ссылка для восстановления пароля.', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _loading ? null : _submit, child: _loading ? const CircularProgressIndicator() : const Text('Отправить')),
        ]),
      ),
    );
  }
}
