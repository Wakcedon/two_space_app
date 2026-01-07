import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_notifier.dart';
import '../utils/responsive.dart';
import '../services/sentry_service.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import '../services/matrix_service.dart';

/// Simplified RegisterScreen using Riverpod for state management
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _nameCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  String? _avatarPath;
  Uint8List? _avatarBytes;
  int _step = 0;

  @override
  void dispose() {
    _nameCtl.dispose();
    _emailCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  int _getPasswordStrength(String password) {
    if (password.length < 6) return 0;
    int strength = 1;
    if (password.length >= 8) strength++;
    if (RegExp(r'[0-9]').hasMatch(password)) strength++;
    if (RegExp(r'[A-Z]').hasMatch(password)) strength++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) strength++;
    return strength;
  }

  String _getPasswordStrengthLabel(int strength) {
    switch (strength) {
      case 0:
      case 1:
        return 'Слабый пароль';
      case 2:
        return 'Средний пароль';
      case 3:
        return 'Хороший пароль';
      default:
        return 'Сильный пароль';
    }
  }

  Color _getPasswordStrengthColor(int strength) {
    switch (strength) {
      case 0:
      case 1:
        return Colors.red;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.amber;
      default:
        return Colors.green;
    }
  }

  Future<void> _handleRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      SentryService.addBreadcrumb('Начало регистрации', category: 'auth');
      
      final notifier = ref.read(authNotifierProvider.notifier);
      
      // For now, just use login (registration logic will be added to AuthNotifier)
      await notifier.login(
        _emailCtl.text.trim(),
        _passCtl.text.trim(),
      );
      
      SentryService.addBreadcrumb('Регистрация успешна', category: 'auth');
      
      // Navigation handled by AuthListener
    } catch (e, stackTrace) {
      SentryService.captureException(
        e,
        stackTrace: stackTrace,
        hint: {'screen': 'register', 'step': _step},
      );
      
      if (!mounted) return;
      _showError('Ошибка регистрации: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Введите email';
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v)) {
      return 'Неверный формат email';
    }
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Введите пароль';
    if (v.length < 6) return 'Минимум 6 символов';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isSmallScreen = MediaQuery.of(context).size.width < 500;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Регистрация'),
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        centerTitle: true,
      ),
      body: Stepper(
        currentStep: _step,
        type: isSmallScreen ? StepperType.vertical : StepperType.horizontal,
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
    );
  }
}
