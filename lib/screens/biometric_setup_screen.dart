import 'package:flutter/material.dart';
import '../services/biometric_auth_service.dart';

class BiometricSetupScreen extends StatefulWidget {
  const BiometricSetupScreen({Key? key}) : super(key: key);

  @override
  State<BiometricSetupScreen> createState() => _BiometricSetupScreenState();
}

class _BiometricSetupScreenState extends State<BiometricSetupScreen> {
  final biometricService = BiometricAuthService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Безопасность'),
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Методы аутентификации',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),

              // Biometric option
              FutureBuilder<bool>(
                future: biometricService.canAuthenticate(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || !snapshot.data!) {
                    return const SizedBox.shrink();
                  }

                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.fingerprint),
                      title: const Text('Биометрическая аутентификация'),
                      subtitle: const Text('Отпечаток пальца или Face ID'),
                      trailing: Switch(
                        value: true,
                        onChanged: (value) async {
                          if (value) {
                            final authenticated =
                                await biometricService.authenticate();
                            if (authenticated) {
                              await biometricService.setBiometricEnabled(true);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Биометрия включена'),
                                  ),
                                );
                              }
                            }
                          }
                        },
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // PIN code option
              Card(
                child: ListTile(
                  leading: const Icon(Icons.lock),
                  title: const Text('PIN-код'),
                  subtitle: const Text('4-6 цифр для защиты'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    _showPinDialog(context, biometricService);
                  },
                ),
              ),
              const SizedBox(height: 24),

              // Info section
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'О безопасности',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Выберите удобный метод для защиты вашего аккаунта. '
                      'Биометрия безопаснее и удобнее, но PIN-код работает везде.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
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

  void _showPinDialog(BuildContext context, BiometricAuthService service) {
    showDialog(
      context: context,
      builder: (ctx) => PinInputDialog(biometricService: service),
    );
  }
}

class PinInputDialog extends StatefulWidget {
  final BiometricAuthService biometricService;

  const PinInputDialog({required this.biometricService});

  @override
  State<PinInputDialog> createState() => _PinInputDialogState();
}

class _PinInputDialogState extends State<PinInputDialog> {
  final _pinController = TextEditingController();
  String? _errorText;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Установить PIN-код'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            decoration: InputDecoration(
              labelText: 'PIN (4-6 цифр)',
              errorText: _errorText,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () async {
            final pin = _pinController.text.trim();
            if (pin.length < 4 || pin.length > 6) {
              setState(() => _errorText = 'PIN должен быть 4-6 цифр');
              return;
            }

            await widget.biometricService.setPinCode(pin);
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('PIN установлен')),
              );
            }
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }
}
