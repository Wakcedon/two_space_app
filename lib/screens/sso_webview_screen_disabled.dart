import 'package:flutter/material.dart';

class SsoWebviewScreen extends StatefulWidget {
  final String idpId; // e.g. 'google' or 'yandex'
  const SsoWebviewScreen({super.key, required this.idpId});

  @override
  State<SsoWebviewScreen> createState() => _SsoWebviewScreenState();
}

class _SsoWebviewScreenState extends State<SsoWebviewScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SSO Вход')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.web, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('SSO Вход через ${widget.idpId}'),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Функция WebView требует расширенной конфигурации'),
          ],
        ),
      ),
    );
  }
}
