import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../config/environment.dart';
import 'otp_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import '../services/matrix_service.dart';
// import '../services/chat_matrix_service.dart'; // kept for future uses

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtl = TextEditingController();
  final _nicknameCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();
  final _auth = AuthService();
  bool _loading = false;
  String? _avatarPath;
  Uint8List? _avatarBytes;
  int _step = 0;

  @override
  void dispose() {
    _nameCtl.dispose();
    _nicknameCtl.dispose();
    _emailCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  Future<void> _finishRegistration() async {
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
  
  Future<void> _register() async {
    // initial registration may simply create the account in the backend, leaving login to later step
    setState(() => _loading = true);
    try {
      await _auth.registerUser(_nameCtl.text.trim(), _emailCtl.text.trim(), _passCtl.text.trim());
      // Continue to finish
      if (mounted) setState(() => _step = 1);
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
        child: Stepper(
          currentStep: _step,
          onStepContinue: () async {
            if (_step == 0) {
              // create basic user account
              await _register();
            } else if (_step == 1) {
              setState(() => _step = 2);
            } else {
              await _finishRegistration();
            }
          },
          onStepCancel: () {
            if (_step > 0) setState(() => _step -= 1);
          },
          steps: [
            Step(title: const Text('Аккаунт'), content: Column(children: [
              TextField(controller: _emailCtl, decoration: const InputDecoration(hintText: 'Email')),
              const SizedBox(height: 8),
              TextField(controller: _passCtl, decoration: const InputDecoration(hintText: 'Пароль (опционально)'), obscureText: true),
            ])),
            Step(title: const Text('Профиль'), content: Column(children: [
              TextField(controller: _nameCtl, decoration: const InputDecoration(hintText: 'Имя')),
              const SizedBox(height: 8),
              TextField(controller: _nicknameCtl, decoration: const InputDecoration(hintText: 'Никнейм')),
            ])),
            Step(title: const Text('Аватар'), content: Column(children: [
              Row(children: [Expanded(child: Text('Аватар (опционально)')), TextButton.icon(onPressed: () async { final res = await FilePicker.platform.pickFiles(type: FileType.image); if (res != null && res.files.isNotEmpty) { setState(() { _avatarPath = res.files.single.path; _avatarBytes = res.files.single.bytes; }); } }, icon: const Icon(Icons.photo), label: const Text('Загрузить'))]),
              const SizedBox(height: 8),
              if (_avatarBytes != null) Image.memory(_avatarBytes!, width: 120, height: 120),
              const SizedBox(height: 16),
              Row(children: [TextButton(onPressed: () => setState(() => _step = 1), child: const Text('Назад')), const Spacer(), _loading ? const CircularProgressIndicator() : ElevatedButton(onPressed: _finishRegistration, child: const Text('Завершить'))])
            ])),
          ],
        ),
      ),
    );
  }
}
