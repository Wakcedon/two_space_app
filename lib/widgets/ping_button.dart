import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/environment.dart';

class PingButton extends StatefulWidget {
  const PingButton({super.key});

  @override
  State<PingButton> createState() => _PingButtonState();
}

class _PingButtonState extends State<PingButton> {
  String message = '';

  void ping() async {
    try {
      final uri = Uri.parse('${Environment.appwritePublicEndpoint}/health');
      final baseHeaders = {
        'x-appwrite-project': Environment.appwriteProjectId,
      };

      // First try without API key
      var res = await http.get(uri, headers: baseHeaders);

      // If unauthorized due to missing scope and we have an API key configured, retry with the key
      if ((res.statusCode == 401 || res.statusCode == 403) && Environment.appwriteApiKey.isNotEmpty) {
        final withKey = {
          ...baseHeaders,
          'x-appwrite-key': Environment.appwriteApiKey,
        };
        res = await http.get(uri, headers: withKey);
      }

      setState(() {
        message = 'Ping: ${res.statusCode} ${res.body}';
      });
    } catch (e) {
      setState(() {
        message = 'Ошибка: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(onPressed: ping, child: const Text('Send Ping')),
        const SizedBox(height: 16),
        Text(message, style: const TextStyle(color: Colors.white)),
      ],
    );
  }
}
