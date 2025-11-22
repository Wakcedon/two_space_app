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

  // Вспомогательная функция для проверки силы пароля
  int _getPasswordStrength(String password) {
    if (password.length < 6) return 0; // Слабый
    int strength = 1;
    if (password.length >= 8) strength++;
    if (RegExp(r'[0-9]').hasMatch(password)) strength++;
    if (RegExp(r'[A-Z]').hasMatch(password)) strength++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) strength++;
    return strength;
  }

  String _getPasswordStrengthLabel(int strength) {
    switch (strength) {
      case 0: return 'Слабый пароль';
      case 1: return 'Слабый пароль';
      case 2: return 'Средний пароль';
      case 3: return 'Хороший пароль';
      default: return 'Сильный пароль';
    }
  }

  Color _getPasswordStrengthColor(int strength) {
    switch (strength) {
      case 0:
      case 1: return Colors.red;
      case 2: return Colors.orange;
      case 3: return Colors.amber;
      default: return Colors.green;
    }
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
      appBar: AppBar(
        title: const Text('Регистрация'),
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (_step + 1) / 3,
                  minHeight: 4,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Theme(
                data: Theme.of(context).copyWith(
                  useMaterial3: true,
                ),
                child: Stepper(
                  currentStep: _step,
                  onStepContinue: _loading ? null : () async {
                    if (_step == 0) {
                      await _register();
                    } else if (_step == 1) {
                      setState(() => _step = 2);
                    } else {
                      await _finishRegistration();
                    }
                  },
                  onStepCancel: _loading ? null : () {
                    if (_step > 0) setState(() => _step -= 1);
                  },
                  steps: [
                    Step(
                      title: const Text('Аккаунт'),
                      content: Column(
                        children: [
                          TextFormField(
                            controller: _emailCtl,
                            decoration: InputDecoration(
                              hintText: 'Email',
                              prefixIcon: const Icon(Icons.email),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passCtl,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: 'Пароль (опционально)',
                              prefixIcon: const Icon(Icons.lock),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                            obscureText: true,
                          ),
                          if (_passCtl.text.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _getPasswordStrengthLabel(_getPasswordStrength(_passCtl.text)),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _getPasswordStrengthColor(_getPasswordStrength(_passCtl.text)),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: _getPasswordStrength(_passCtl.text) / 5,
                                      minHeight: 6,
                                      backgroundColor: Colors.grey[300],
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        _getPasswordStrengthColor(_getPasswordStrength(_passCtl.text)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Минимум 6 символов',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    Step(
                      title: const Text('Профиль'),
                      content: Column(
                        children: [
                          TextFormField(
                            controller: _nameCtl,
                            decoration: InputDecoration(
                              hintText: 'Имя',
                              prefixIcon: const Icon(Icons.person),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _nicknameCtl,
                            decoration: InputDecoration(
                              hintText: 'Никнейм',
                              prefixIcon: const Icon(Icons.badge),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Step(
                      title: const Text('Аватар'),
                      content: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: const Text(
                                  'Аватар (опционально)',
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () async {
                                  final res = await FilePicker.platform.pickFiles(type: FileType.image);
                                  if (res != null && res.files.isNotEmpty) {
                                    setState(() {
                                      _avatarPath = res.files.single.path;
                                      _avatarBytes = res.files.single.bytes;
                                    });
                                  }
                                },
                                icon: const Icon(Icons.add_a_photo),
                                label: const Text('Загрузить'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_avatarBytes != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                _avatarBytes!,
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                              ),
                            ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}