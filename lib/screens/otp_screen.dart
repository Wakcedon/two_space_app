import 'dart:async';
import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class OtpScreen extends StatefulWidget {
  final String phone;
  const OtpScreen({super.key, required this.phone});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  int _secondsLeft = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _secondsLeft = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        if (_secondsLeft > 0) _secondsLeft--; else _timer?.cancel();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _controller.text.trim();
    if (code.isEmpty || code.length < 4) return; // basic guard
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Color(SettingsService.themeNotifier.value.primaryColorValue);
    return Scaffold(
      appBar: AppBar(title: const Text('Подтвердите телефон')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Мы отправили код на ${widget.phone}', style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Введите код'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              onPressed: _loading ? null : _submit,
              child: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Подтвердить'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _secondsLeft > 0 ? null : () {
                // Signal caller to resend by popping null and letting caller re-send token
                Navigator.of(context).pop(null);
              },
              child: Text(_secondsLeft > 0 ? 'Повторная отправка через $_secondsLeft с' : 'Отправить код повторно'),
            ),
          ],
        ),
      ),
    );
  }
}
