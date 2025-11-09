import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/appwrite_service.dart';
import '../services/settings_service.dart';
import '../widgets/app_logo.dart';
import 'package:two_space_app/utils/responsive.dart';
import 'home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final AuthService _auth = AuthService();
  bool _loading = false;
  bool _obscure = true;
  String? _errorMessage;
  // password strength flags
  bool _hasUpper = false;
  bool _hasNumber = false;
  bool _hasSpecial = false;
  bool _hasLength = false;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void _onEmailFieldChanged(String raw) {
    final sanitized = raw.replaceAll(RegExp(r'[^@a-zA-Z0-9._-]'), '');
    if (sanitized != raw) {
      emailController.value = TextEditingValue(text: sanitized, selection: TextSelection.collapsed(offset: sanitized.length));
    }
  }


  String? _validateName(String? v) {
    if (v == null || v.trim().isEmpty) return 'Введите имя';
    if (v.trim().length < 3) return 'Имя должно содержать не менее 3 символов';
    return null;
  }

  String? _validateEmailOrPhone(String? v) {
    if (v == null || v.trim().isEmpty) return 'Поле не может быть пустым';
    final val = v.trim();
    final emailRegex = RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+");
    if (!emailRegex.hasMatch(val)) return 'Введите корректный email';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Введите пароль';
    if (v.length < 6) return 'Пароль должен быть не менее 6 символов';
    return null;
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      var identifier = emailController.text.trim();
      await _auth.registerUser(nameController.text.trim(), identifier, passwordController.text.trim());
      // Try to auto-login, but don't treat login failure as registration failure.
      try {
        await _auth.loginUser(identifier, passwordController.text.trim());
        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
        return;
      } catch (loginErr) {
        if (!mounted) return;
        // Registration succeeded but login failed. Prompt user to login manually.
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Регистрация успешна. Пожалуйста, войдите в систему.')));
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }
    } catch (e) {
      final fullMsg = AppwriteService.readableError(e);
      // If the original exception looks like HTML, don't show raw body in UI.
      final isHtml = fullMsg.contains('<!DOCTYPE') || fullMsg.contains('<html') || fullMsg.trimLeft().startsWith('<');
      final shortMsg = fullMsg.length > 300 ? '${fullMsg.substring(0, 300)}...' : fullMsg;
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Ошибка регистрации: ${isHtml ? 'Серверная ошибка. Проверьте логи.' : shortMsg}';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onPasswordChanged(String v) {
    setState(() {
      _hasLength = v.length >= 8;
      _hasUpper = v.contains(RegExp(r'[A-ZА-Я]'));
      _hasNumber = v.contains(RegExp(r'[0-9]'));
      _hasSpecial = v.contains(RegExp(r'[!@#\$%\^&*(),.?":{}|<>]'));
    });
  }

  @override
  Widget build(BuildContext context) {
    const themeFill = Color(0xFF111217);
    final primaryColor = Color(SettingsService.themeNotifier.value.primaryColorValue);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0C10),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 24 * Responsive.scaleWidth(context), vertical: 36 * Responsive.scaleHeight(context)),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: 320 * Responsive.scaleWidth(context),
                maxWidth: 520 * Responsive.scaleWidth(context),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Hero(
                    tag: 'logo',
                    flightShuttleBuilder: (flightContext, animation, flightDirection, fromHeroContext, toHeroContext) {
                      return Material(
                        color: Colors.transparent,
                        child: toHeroContext.widget,
                      );
                    },
                    child: const AppLogo(large: true),
                  ),
                  SizedBox(height: 20 * Responsive.scaleHeight(context)),
                  Text('Регистрация', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white)),
                  SizedBox(height: 20 * Responsive.scaleHeight(context)),
                  Column(
                    children: [
                      if (_errorMessage != null) Padding(
                        padding: EdgeInsets.only(bottom: 12.0 * Responsive.scaleHeight(context)),
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(12 * Responsive.scaleFor(context)),
                          decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(8 * Responsive.scaleWidth(context))),
                          child: Text(_errorMessage!, style: const TextStyle(color: Colors.white)),
                        ),
                      ),
                      if (_loading) const LinearProgressIndicator(minHeight: 3),
                      TextFormField(
                        controller: nameController,
                        validator: _validateName,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Имя',
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: themeFill,
                          prefixIcon: const Icon(Icons.person, color: Colors.white54),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(30 * Responsive.scaleWidth(context)), borderSide: BorderSide.none),
                          contentPadding: EdgeInsets.symmetric(horizontal: 20 * Responsive.scaleWidth(context), vertical: 18 * Responsive.scaleHeight(context)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailController,
                        validator: _validateEmailOrPhone,
                        onChanged: _onEmailFieldChanged,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Email',
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: themeFill,
                          prefixIcon: const Icon(Icons.email, color: Colors.white54),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(30 * Responsive.scaleWidth(context)), borderSide: BorderSide.none),
                          contentPadding: EdgeInsets.symmetric(horizontal: 20 * Responsive.scaleWidth(context), vertical: 18 * Responsive.scaleHeight(context)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: passwordController,
                        obscureText: _obscure,
                        validator: _validatePassword,
                        onChanged: _onPasswordChanged,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Пароль',
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: themeFill,
                          prefixIcon: const Icon(Icons.lock, color: Colors.white54),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, color: Colors.white54),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(30 * Responsive.scaleWidth(context)), borderSide: BorderSide.none),
                          contentPadding: EdgeInsets.symmetric(horizontal: 20 * Responsive.scaleWidth(context), vertical: 18 * Responsive.scaleHeight(context)),
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Password strength hints
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 6.0 * Responsive.scaleHeight(context)),
                        child: Row(children: [
                          _pwHint('8+ символов', _hasLength),
                          const SizedBox(width: 8),
                          _pwHint('Заглавная', _hasUpper),
                          const SizedBox(width: 8),
                          _pwHint('Цифра', _hasNumber),
                          const SizedBox(width: 8),
                          _pwHint('Спецсимвол', _hasSpecial),
                        ]),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            padding: EdgeInsets.symmetric(vertical: 14 * Responsive.scaleHeight(context)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30 * Responsive.scaleWidth(context))),
                          ),
                          onPressed: _loading ? null : _register,
                          child: _loading ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text('Зарегистрироваться', style: TextStyle(color: Theme.of(context).primaryColor.computeLuminance() > 0.6 ? Colors.black : Colors.white)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => Navigator.pushNamed(context, '/login'),
                        child: const Text('Уже есть аккаунт?', style: TextStyle(color: Colors.white70)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
  }

  Widget _pwHint(String text, bool ok) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? Colors.greenAccent : Colors.white54, size: 16),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(color: ok ? Colors.greenAccent : Colors.white54, fontSize: 12)),
    ]);
  }
}
