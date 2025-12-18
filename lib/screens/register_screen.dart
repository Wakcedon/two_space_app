import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_notifier.dart';
import '../utils/responsive.dart';
import '../services/sentry_service.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';

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
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16.0 * Responsive.scaleWidth(context)),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                SizedBox(height: 16 * Responsive.scaleHeight(context)),
                
                // Progress indicator
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
                SizedBox(height: 24 * Responsive.scaleHeight(context)),
                
                // Step content
                if (_step == 0) _buildAccountStep(),
                if (_step == 1) _buildProfileStep(),
                if (_step == 2) _buildAvatarStep(),
                
                SizedBox(height: 24 * Responsive.scaleHeight(context)),
                
                // Navigation buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_step > 0)
                      TextButton(
                        onPressed: authState.isLoading
                            ? null
                            : () => setState(() => _step--),
                        child: const Text('Назад'),
                      )
                    else
                      const SizedBox.shrink(),
                    
                    ElevatedButton(
                      onPressed: authState.isLoading
                          ? null
                          : () async {
                              if (_step < 2) {
                                if (_formKey.currentState!.validate()) {
                                  setState(() => _step++);
                                }
                              } else {
                                await _handleRegistration();
                              }
                            },
                      child: authState.isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_step < 2 ? 'Далее' : 'Зарегистрироваться'),
                    ),
                  ],
                ),
                
                SizedBox(height: 20 * Responsive.scaleHeight(context)),
                
                // Login link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Уже есть аккаунт? ',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Войти'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Шаг 1: Аккаунт',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 24),
        
        TextFormField(
          controller: _emailCtl,
          decoration: InputDecoration(
            hintText: 'Email',
            prefixIcon: const Icon(Icons.email),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          keyboardType: TextInputType.emailAddress,
          validator: _validateEmail,
        ),
        const SizedBox(height: 16),
        
        TextFormField(
          controller: _passCtl,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Пароль',
            prefixIcon: const Icon(Icons.lock),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          obscureText: true,
          validator: _validatePassword,
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
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildProfileStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Шаг 2: Профиль',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 24),
        
        TextFormField(
          controller: _nameCtl,
          decoration: InputDecoration(
            hintText: 'Имя',
            prefixIcon: const Icon(Icons.person),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Введите имя' : null,
        ),
      ],
    );
  }

  Widget _buildAvatarStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Шаг 3: Аватар (опционально)',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 24),
        
        Center(
          child: Column(
            children: [
              if (_avatarBytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(60),
                  child: Image.memory(
                    _avatarBytes!,
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                )
              else
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  ),
                  child: Icon(
                    Icons.person,
                    size: 60,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              
              const SizedBox(height: 16),
              
              ElevatedButton.icon(
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
                label: const Text('Загрузить фото'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
