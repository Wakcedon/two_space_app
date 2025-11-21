import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  final _auth = AuthService();

  @override
  void dispose() {
    _emailCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await _auth.loginUser(_emailCtl.text.trim(), _passCtl.text.trim());
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _validateEmail(String? v) => (v == null || v.trim().isEmpty) ? 'Введите email' : null;
  String? _validatePassword(String? v) => (v == null || v.isEmpty) ? 'Введите пароль' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: _emailCtl, decoration: const InputDecoration(hintText: 'Email'), validator: _validateEmail),
            const SizedBox(height: 8),
            TextFormField(controller: _passCtl, decoration: const InputDecoration(hintText: 'Пароль'), obscureText: true, validator: _validatePassword),
            const SizedBox(height: 12),
            _loading ? const CircularProgressIndicator() : ElevatedButton(onPressed: _login, child: const Text('Войти')),
            TextButton(onPressed: () => Navigator.pushNamed(context, '/register'), child: const Text('Создать аккаунт')),
          ]),
        ),
      ),
    );
  }
}

