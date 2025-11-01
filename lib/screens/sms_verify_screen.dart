import 'package:flutter/material.dart';
import 'dart:async';

import 'package:two_space_app/services/auth_service.dart';
import 'package:two_space_app/services/appwrite_service.dart';
import 'package:two_space_app/services/settings_service.dart';
import 'package:two_space_app/screens/home_screen.dart';

class SmsVerifyScreen extends StatefulWidget {
  final String phone;
  final String? userId;
  const SmsVerifyScreen({super.key, required this.phone, this.userId});

  @override
  State<SmsVerifyScreen> createState() => _SmsVerifyScreenState();
}

class _SmsVerifyScreenState extends State<SmsVerifyScreen> {
  final TextEditingController _code = TextEditingController();
  final AuthService _auth = AuthService();
  bool _loading = false;
  String? _userId;
  Timer? _resendTimer;
  int _resendSeconds = 0;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _code.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _userId = widget.userId;
  }

  // ...existing code...

  Future<void> _verify() async {
    if (_code.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await _auth.createSessionFromToken(_userId ?? '', _code.text.trim());
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false);
    } catch (e) {
      final msg = AppwriteService.readableError(e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка проверки кода: $msg')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_resendSeconds > 0) return;
    setState(() => _resendSeconds = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        _resendSeconds -= 1;
        if (_resendSeconds <= 0) {
          _resendTimer?.cancel();
        }
      });
    });
    try {
      final resp = await _auth.sendPhoneToken(widget.phone);
      if (resp is Map && resp.containsKey('userId')) _userId = resp['userId'].toString();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Код повторно отправлен')));
    } catch (e) {
      final msg = AppwriteService.readableError(e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка отправки: $msg')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Подтверждение номера')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('Код отправлен на ${widget.phone}'),
            const SizedBox(height: 12),
            ValueListenableBuilder<bool>(
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
                  child: TextField(controller: _code, decoration: const InputDecoration(hintText: 'Код из SMS')),
                );
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loading ? null : _verify, child: _loading ? const CircularProgressIndicator() : const Text('Подтвердить')),
            const SizedBox(height: 8),
            TextButton(onPressed: _resendSeconds > 0 ? null : _resend, child: Text(_resendSeconds > 0 ? 'Отправить снова ($_resendSeconds)' : 'Отправить снова')),
          ],
        ),
      ),
    );
  }
}
