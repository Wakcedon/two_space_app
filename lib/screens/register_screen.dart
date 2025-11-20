import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/appwrite_service.dart';
import '../config/environment.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:file_picker/file_picker.dart';
import 'sso_webview_screen.dart';
import 'otp_screen.dart';
import '../services/settings_service.dart';
import '../widgets/app_logo.dart';
import 'package:two_space_app/utils/responsive.dart';
import 'home_screen.dart';
import '../widgets/glass_card.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController nickController = TextEditingController();
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
  bool _showPwDetails = false;
  String? _avatarPath;

  @override
  void dispose() {
    nameController.dispose();
    nickController.dispose();
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
        // If email token flow configured, try passwordless confirmation
        if (Environment.useMatrix && Environment.matrixEmailTokenEndpoint.isNotEmpty) {
          try {
            final token = await _auth.sendEmailToken(identifier);
            if (!mounted) return;
            final code = await Navigator.push<String?>(context, MaterialPageRoute(builder: (_) => OtpScreen(phone: identifier)));
            if (code != null && code.isNotEmpty) {
              try {
                await _auth.createSessionFromToken(token['userId'] ?? identifier, code);
                if (!mounted) return;
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
                return;
              } catch (_) {}
            }
          } catch (_) {}
        }
        // Fallback to classic login after registration
        await _auth.loginUser(identifier, passwordController.text.trim());
        if (_avatarPath != null && _avatarPath!.isNotEmpty) {
          try {
            final id = await AppwriteService.uploadAvatar(_avatarPath!);
            // set avatar in Matrix account
            await AppwriteService.updateAccount(prefs: {'avatarUrl': id['viewUrl'] ?? ''});
          } catch (_) {}
        }
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
  final theme = Theme.of(context);
  final themeFill = theme.inputDecorationTheme.fillColor ?? theme.colorScheme.surface;
  final primaryColor = Color(SettingsService.themeNotifier.value.primaryColorValue);
  final textColor = theme.textTheme.bodyLarge?.color ?? theme.colorScheme.onBackground;
  final hintColor = theme.hintColor;
    final canRegister = !_loading && _validateName(nameController.text) == null && _validateEmailOrPhone(emailController.text) == null && _hasLength && (_hasUpper || _hasNumber || _hasSpecial);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                child: GlassCard(
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
                      Text('Регистрация', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: textColor)),
                      SizedBox(height: 20 * Responsive.scaleHeight(context)),

                      // Form column
                      Column(
                        children: [
                          if (_errorMessage != null)
                            Padding(
                              padding: EdgeInsets.only(bottom: 12.0 * Responsive.scaleHeight(context)),
                              child: Container(
                                width: double.infinity,
                                padding: EdgeInsets.all(12 * Responsive.scaleFor(context)),
                                decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(8 * Responsive.scaleWidth(context))),
                                child: Text(_errorMessage!, style: const TextStyle(color: Colors.white)),
                              ),
                            ),

                          if (_errorMessage != null)
                            Padding(
                              padding: EdgeInsets.only(bottom: 12.0 * Responsive.scaleHeight(context)),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.login_outlined),
                                  label: const Text('Копировать URL SSO входа'),
                                  onPressed: () {
                                    final hs = Environment.matrixHomeserverUrl.trim();
                                    if (hs.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Homeserver не настроен')));
                                      return;
                                    }
                                    var base = hs;
                                    if (!base.startsWith('http://') && !base.startsWith('https://')) base = 'https://' + base;
                                    base = base.replaceAll(RegExp(r'/$'), '');
                                    final sso = Uri.parse(base + '/_matrix/client/v3/login/sso/redirect').toString();
                                    Clipboard.setData(ClipboardData(text: sso));
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SSO URL скопирован в буфер обмена')));
                                  },
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton(
                                  onPressed: () {
                                    showDialog(context: context, builder: (_) => AlertDialog(
                                      title: const Text('Помощь: регистрация отключена'),
                                      content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        const Text('Если при регистрации вы видите сообщение о том, что регистрация отключена или сервер возвращает 502/403, выполните следующее на сервере:'),
                                        const SizedBox(height: 8),
                                        const Text('1) Проверьте `homeserver.yaml` и при необходимости добавьте:'),
                                        const SelectableText('   enable_registration_without_verification: true'),
                                        const SizedBox(height: 6),
                                        const Text('2) Перезапустите Synapse: `docker compose down && docker compose up -d`'),
                                        const SizedBox(height: 6),
                                        const Text('3) Проверьте логи: `docker compose logs -f synapse`'),
                                        const SizedBox(height: 8),
                                        const Text('Альтернатива: включите OIDC (Google/Yandex) в homeserver.yaml и используйте кнопку SSO.'),
                                      ])),
                                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть'))],
                                    ));
                                  },
                                  child: const Text('Показать инструкции по исправлению сервера'),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    final ok = await Navigator.push<bool?>(context, MaterialPageRoute(builder: (_) => SsoWebviewScreen(idpId: 'google')));
                                    if (ok == true) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Вход через Google завершён')));
                                    }
                                  },
                                  icon: const Icon(Icons.login),
                                  label: const Text('Войти через Google'),
                                ),
                                const SizedBox(height: 6),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    final ok = await Navigator.push<bool?>(context, MaterialPageRoute(builder: (_) => SsoWebviewScreen(idpId: 'yandex')));
                                    if (ok == true) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Вход через Yandex завершён')));
                                    }
                                  },
                                  icon: const Icon(Icons.person),
                                  label: const Text('Войти через Yandex'),
                                ),
                              ]),
                            ),

                          if (_loading) const LinearProgressIndicator(minHeight: 3),

                          // Form fields
                          TextFormField(
                            controller: nameController,
                            validator: _validateName,
                            style: TextStyle(color: textColor),
                            decoration: InputDecoration(
                              hintText: 'Имя',
                              hintStyle: TextStyle(color: hintColor),
                              filled: true,
                              fillColor: themeFill,
                              prefixIcon: Icon(Icons.person, color: theme.colorScheme.onSurface.withAlpha(180)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30 * Responsive.scaleWidth(context)), borderSide: BorderSide.none),
                              contentPadding: EdgeInsets.symmetric(horizontal: 20 * Responsive.scaleWidth(context), vertical: 18 * Responsive.scaleHeight(context)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: nickController,
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Введите никнейм' : null,
                            style: TextStyle(color: textColor),
                            decoration: InputDecoration(
                              hintText: 'Никнейм (уникальное имя)',
                              hintStyle: TextStyle(color: hintColor),
                              filled: true,
                              fillColor: themeFill,
                              prefixIcon: Icon(Icons.alternate_email, color: theme.colorScheme.onSurface.withAlpha(180)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30 * Responsive.scaleWidth(context)), borderSide: BorderSide.none),
                              contentPadding: EdgeInsets.symmetric(horizontal: 20 * Responsive.scaleWidth(context), vertical: 18 * Responsive.scaleHeight(context)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(child: Text('Аватар (опционально)', style: TextStyle(color: textColor))),
                            TextButton.icon(onPressed: () async {
                              final res = await FilePicker.platform.pickFiles();
                              if (res != null && res.files.isNotEmpty) {
                                _avatarPath = res.files.single.path;
                                if (mounted) setState(() {});
                              }
                            }, icon: const Icon(Icons.photo_camera), label: const Text('Загрузить')),
                          ]),
                          TextFormField(
                            controller: emailController,
                            validator: _validateEmailOrPhone,
                            onChanged: _onEmailFieldChanged,
                            keyboardType: TextInputType.emailAddress,
                            style: TextStyle(color: textColor),
                            decoration: InputDecoration(
                              hintText: 'Email',
                              hintStyle: TextStyle(color: hintColor),
                              filled: true,
                              fillColor: themeFill,
                              prefixIcon: Icon(Icons.email, color: theme.colorScheme.onSurface.withAlpha(180)),
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
                            style: TextStyle(color: textColor),
                            decoration: InputDecoration(
                              hintText: 'Пароль',
                              hintStyle: TextStyle(color: hintColor),
                              filled: true,
                              fillColor: themeFill,
                              prefixIcon: Icon(Icons.lock, color: theme.colorScheme.onSurface.withAlpha(180)),
                              suffixIcon: IconButton(
                                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, color: theme.colorScheme.onSurface.withAlpha(180)),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30 * Responsive.scaleWidth(context)), borderSide: BorderSide.none),
                              contentPadding: EdgeInsets.symmetric(horizontal: 20 * Responsive.scaleWidth(context), vertical: 18 * Responsive.scaleHeight(context)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => setState(() => _showPwDetails = !_showPwDetails),
                              child: Text(_showPwDetails ? 'Скрыть' : 'Подробнее', style: TextStyle(color: theme.colorScheme.primary)),
                            ),
                          ),
                          if (_showPwDetails)
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 6.0 * Responsive.scaleHeight(context)),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                _pwHint('8+ символов', _hasLength, theme: theme),
                                const SizedBox(height: 6),
                                _pwHint('Заглавная буква', _hasUpper, theme: theme),
                                const SizedBox(height: 6),
                                _pwHint('Цифра', _hasNumber, theme: theme),
                                const SizedBox(height: 6),
                                _pwHint('Спецсимвол', _hasSpecial, theme: theme),
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
                              onPressed: canRegister ? _register : null,
                              child: _loading ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onPrimary)) : Text('Зарегистрироваться', style: TextStyle(color: theme.colorScheme.onPrimary)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => Navigator.pushNamed(context, '/login'),
                            child: Text('Уже есть аккаунт?', style: TextStyle(color: theme.colorScheme.onBackground.withAlpha((0.85 * 255).round()))),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pwHint(String text, bool ok, {ThemeData? theme}) {
    final th = theme ?? Theme.of(context);
    final okColor = Colors.greenAccent;
    final badColor = th.colorScheme.onBackground.withAlpha((0.6 * 255).round());
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? okColor : badColor, size: 16),
      const SizedBox(width: 8),
      Text(text, style: TextStyle(color: ok ? okColor : badColor, fontSize: 13)),
    ]);
  }
}
