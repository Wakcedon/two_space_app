import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../services/auth_service.dart';

class TfaSetupScreen extends StatefulWidget {
  const TfaSetupScreen({super.key});

  @override
  State<TfaSetupScreen> createState() => _TfaSetupScreenState();
}

class _TfaSetupScreenState extends State<TfaSetupScreen> {
  final AuthService _auth = AuthService();
  String? _otpauthUrl;
  String? _secret;
  bool _loading = true;
  final _codeController = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final js = await _auth.requestTotpSetup();
      // Expect server to return { 'otpauth': 'otpauth://totp/...', 'secret': 'ABC123' }
      setState(() {
        _otpauthUrl = js['otpauth']?.toString();
        _secret = js['secret']?.toString();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _verify() async {
    setState(() => _loading = true);
    try {
      await _auth.verifyTotpSetup(_codeController.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('2FA enabled')));
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Включить двухфакторную аутентификацию')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _loading ? const Center(child: CircularProgressIndicator()) : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) Text('Ошибка: $_error', style: const TextStyle(color: Colors.red)),
            if (_otpauthUrl != null) Center(child: Column(mainAxisSize: MainAxisSize.min, children: [SelectableText(_otpauthUrl!), IconButton(icon: const Icon(Icons.copy), onPressed: () { Clipboard.setData(ClipboardData(text: _otpauthUrl!)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Код скопирован'))); })])),
            const SizedBox(height: 12),
            if (_secret != null) Row(children: [Expanded(child: SelectableText('Код: $_secret')), IconButton(icon: const Icon(Icons.copy), onPressed: () { /* copy */ })]),
            const SizedBox(height: 12),
            Text('Откройте приложение генератора (Google Authenticator, Authy) и отсканируйте QR-код; введите 6-значный код', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            TextField(controller: _codeController, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: '6-значный код')), 
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _verify, child: const Text('Подтвердить и включить'))
          ],
        ),
      ),
    );
  }
}
