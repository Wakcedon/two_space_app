import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'otp_screen.dart';
import 'sso_webview_screen.dart';

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
  bool _ssoLoading = false;

  @override
  void dispose() {
    _emailCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    if (_loading || _ssoLoading) return; // Защита от двойного клика
    setState(() => _loading = true);
    try {
      final identifier = _emailCtl.text.trim();
      // Phone flow
      if (identifier.startsWith('+')) {
        final token = await _auth.sendPhoneToken(identifier);
        if (!mounted) return;
        final code = await Navigator.push<String?>(context, MaterialPageRoute(builder: (_) => OtpScreen(phone: identifier)));
        if (code == null || code.isEmpty) return;
        await _auth.createSessionFromToken(token is Map && token.containsKey('userId') ? token['userId'] : identifier, code);
      } else {
        final password = _passCtl.text.trim();
        if (password.isEmpty) {
          final token = await _auth.sendEmailToken(identifier);
          if (!mounted) return;
          final code = await Navigator.push<String?>(context, MaterialPageRoute(builder: (_) => OtpScreen(phone: identifier)));
          if (code == null || code.isEmpty) return;
          await _auth.createSessionFromToken(token is Map && token.containsKey('userId') ? token['userId'] : identifier, code);
        } else {
          await _auth.loginUser(identifier, password);
        }
      }
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _ssoButtons() {
    final isSmallScreen = MediaQuery.of(context).size.width < 500;
    
    if (isSmallScreen) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading || _ssoLoading ? null : () async {
                if (_ssoLoading) return;
                setState(() => _ssoLoading = true);
                try {
                  final ok = await Navigator.push<bool?>(context, MaterialPageRoute(builder: (_) => SsoWebviewScreen(idpId: 'google')));
                  if (ok == true && mounted) Navigator.pushReplacementNamed(context, '/home');
                } finally {
                  if (mounted) setState(() => _ssoLoading = false);
                }
              },
              icon: const Icon(Icons.login),
              label: const Text('Войти через Google'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading || _ssoLoading ? null : () async {
                if (_ssoLoading) return;
                setState(() => _ssoLoading = true);
                try {
                  final ok = await Navigator.push<bool?>(context, MaterialPageRoute(builder: (_) => SsoWebviewScreen(idpId: 'yandex')));
                  if (ok == true && mounted) Navigator.pushReplacementNamed(context, '/home');
                } finally {
                  if (mounted) setState(() => _ssoLoading = false);
                }
              },
              icon: const Icon(Icons.person),
              label: const Text('Войти через Yandex'),
            ),
          ),
        ],
      );
    }
    
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Expanded(
        child: ElevatedButton.icon(
          onPressed: _loading || _ssoLoading ? null : () async {
            if (_ssoLoading) return;
            setState(() => _ssoLoading = true);
            try {
              final ok = await Navigator.push<bool?>(context, MaterialPageRoute(builder: (_) => SsoWebviewScreen(idpId: 'google')));
              if (ok == true && mounted) Navigator.pushReplacementNamed(context, '/home');
            } finally {
              if (mounted) setState(() => _ssoLoading = false);
            }
          },
          icon: const Icon(Icons.login),
          label: const Text('Google'),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: ElevatedButton.icon(
          onPressed: _loading || _ssoLoading ? null : () async {
            if (_ssoLoading) return;
            setState(() => _ssoLoading = true);
            try {
              final ok = await Navigator.push<bool?>(context, MaterialPageRoute(builder: (_) => SsoWebviewScreen(idpId: 'yandex')));
              if (ok == true && mounted) Navigator.pushReplacementNamed(context, '/home');
            } finally {
              if (mounted) setState(() => _ssoLoading = false);
            }
          },
          icon: const Icon(Icons.person),
          label: const Text('Yandex'),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 500;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _emailCtl,
              decoration: InputDecoration(
                hintText: 'Email',
                prefixIcon: const Icon(Icons.email),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passCtl,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'Password',
                prefixIcon: const Icon(Icons.lock),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _login,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('Login'),
            ),
            const SizedBox(height: 12),
            if (isSmallScreen) _ssoButtons(),
          ],
        ),
      ),
    );
  }
}