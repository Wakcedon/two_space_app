import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../config/environment.dart';
import 'otp_screen.dart';
import 'package:file_picker/file_picker.dart';
import '../services/matrix_service.dart';
// import '../services/chat_matrix_service.dart'; // kept for future uses

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();
  final _auth = AuthService();
  bool _loading = false;
  String? _avatarPath;

  @override
  void dispose() {
    _nameCtl.dispose();
    _emailCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    setState(() => _loading = true);
    try {
      await _auth.registerUser(_nameCtl.text.trim(), _emailCtl.text.trim(), _passCtl.text.trim());
      if (!mounted) return;
      // If Matrix email-token endpoint is configured, try auto-confirm and login via token
      if (Environment.useMatrix && Environment.matrixEmailTokenEndpoint.isNotEmpty) {
        try {
          final token = await _auth.sendEmailToken(_emailCtl.text.trim());
          if (!mounted) return;
          final code = await Navigator.push<String?>(context, MaterialPageRoute(builder: (_) => OtpScreen(phone: _emailCtl.text.trim())));
          if (code != null && code.isNotEmpty) {
            await _auth.createSessionFromToken(token is Map && token.containsKey('userId') ? token['userId'] : _emailCtl.text.trim(), code);
            // If avatar selected, upload and set
            if (_avatarPath != null && _avatarPath!.isNotEmpty) {
              try {
                final up = await MatrixService.uploadFileToStorage(_avatarPath!, filename: null);
                final avatarUrl = up['viewUrl']?.toString() ?? '';
                if (avatarUrl.isNotEmpty) await MatrixService.updateAccount(name: null, prefs: {'avatarUrl': avatarUrl});
              } catch (_) {}
            }
            if (!mounted) return;
            Navigator.pushReplacementNamed(context, '/home');
            return;
          }
        } catch (_) {}
      }
      // fallback: login with password
      await _auth.loginUser(_emailCtl.text.trim(), _passCtl.text.trim());
      // Avatar upload fallback
      if (_avatarPath != null && _avatarPath!.isNotEmpty) {
        try {
          final up = await MatrixService.uploadFileToStorage(_avatarPath!, filename: null);
          final avatarUrl = up['viewUrl']?.toString() ?? '';
          if (avatarUrl.isNotEmpty) await MatrixService.updateAccount(name: null, prefs: {'avatarUrl': avatarUrl});
        } catch (_) {}
      }
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Registration failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Регистрация')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _nameCtl, decoration: const InputDecoration(hintText: 'Имя')),
          const SizedBox(height: 8),
          TextField(controller: _emailCtl, decoration: const InputDecoration(hintText: 'Email')),
          const SizedBox(height: 8),
          Row(children: [Expanded(child: Text('Аватар (опционно)')), TextButton.icon(onPressed: () async { final res = await FilePicker.platform.pickFiles(type: FileType.image); if (res != null && res.files.isNotEmpty) { setState(() { _avatarPath = res.files.single.path; }); } }, icon: const Icon(Icons.photo), label: const Text('Загрузить'))]),
          const SizedBox(height: 8),
          TextField(controller: _passCtl, decoration: const InputDecoration(hintText: 'Пароль'), obscureText: true),
          const SizedBox(height: 12),
          _loading ? const CircularProgressIndicator() : ElevatedButton(onPressed: _register, child: const Text('Зарегистрироваться')),
        ]),
      ),
    );
  }
}
