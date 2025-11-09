import 'dart:io';
import 'package:flutter/material.dart';
import '../services/update_service.dart';

class UpdateScreen extends StatefulWidget {
  final UpdateInfo info;
  const UpdateScreen({Key? key, required this.info}) : super(key: key);

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  double _progress = 0.0;
  bool _downloading = false;
  bool _installing = false;
  String? _error;
  bool _verifying = false;
  String _selectedAbi = '';

  Future<void> _startDownload() async {
    // Start download state
    if (!mounted) return;
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0.0;
    });

    final apkPath = await UpdateService.downloadApk(widget.info.updateUrl, onProgress: (p) {
      if (!mounted) return;
      setState(() => _progress = p);
    });

    if (!mounted) return;
    setState(() => _downloading = false);
    if (apkPath == null) {
      setState(() => _error = 'Не удалось скачать обновление');
      return;
    }

    // Verify sha256 if provided
    if (widget.info.sha256 != null && widget.info.sha256!.isNotEmpty) {
      if (!mounted) return;
      setState(() => _verifying = true);
      final ok = await UpdateService.verifySha256(apkPath, widget.info.sha256!);
      if (!mounted) return;
      setState(() => _verifying = false);
      if (!ok) {
        setState(() => _error = 'Скачанный файл не прошёл проверку целостности (sha256)');
        return;
      }
    }

    // On Android, ensure install permission then request install
    if (Platform.isAndroid) {
      final canInstall = await UpdateService.canRequestInstallPackages();
      if (!canInstall) {
        if (!mounted) return;
        final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
          title: const Text('Разрешение на установку'),
          content: const Text('Чтобы установить обновление, разрешите установку приложений из этого источника.'),
          actions: [TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Отмена')), TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Открыть настройки'))],
        ));
        if (ok == true) {
          await UpdateService.openInstallSettings();
        } else {
          if (!mounted) return;
          setState(() => _error = 'Нужны разрешения для установки');
          return;
        }
      }
    }

    if (!mounted) return;
    setState(() => _installing = true);
    final installed = await UpdateService.installApk(apkPath);
    if (!mounted) return;
    setState(() => _installing = false);
    if (!installed && mounted) setState(() => _error = 'Установка не удалась');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Modern full-screen card style similar to Telegram/Discord
    final forced = widget.info.forceUpdate;
    // Determine displayed ABI from the UpdateInfo if available
    try {
      if (widget.info.selectedAbi != null && widget.info.selectedAbi!.isNotEmpty) _selectedAbi = widget.info.selectedAbi!;
    } catch (_) {}
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 24),
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(16),
                    color: theme.cardColor,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(color: theme.colorScheme.primary.withAlpha((0.14 * 255).round()), borderRadius: BorderRadius.circular(22)),
                            child: Icon(Icons.system_update, size: 44, color: theme.colorScheme.primary),
                          ),
                          const SizedBox(height: 16),
                          Text('Доступно обновление', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text(widget.info.latestVersion, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurface.withAlpha((0.9 * 255).round()))),
                          if (_selectedAbi.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: theme.colorScheme.primary.withAlpha((0.12 * 255).round()), borderRadius: BorderRadius.circular(8)), child: Text(_selectedAbi, style: theme.textTheme.bodySmall)),
                          ],
                          const SizedBox(height: 18),
                          Align(alignment: Alignment.centerLeft, child: Text('Что нового', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                          const SizedBox(height: 8),
                          Container(
                            height: 160,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: theme.scaffoldBackgroundColor.withAlpha((0.03 * 255).round()), borderRadius: BorderRadius.circular(12)),
                            child: SingleChildScrollView(child: Text(widget.info.notes.isNotEmpty ? widget.info.notes : 'Описание отсутствует', style: theme.textTheme.bodyMedium)),
                          ),
                          const SizedBox(height: 18),
                          if (_error != null) ...[
                            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                            const SizedBox(height: 12),
                          ],
                          if (_downloading) ...[
                            Text('Скачивание... ${((_progress * 100).clamp(0, 100)).toStringAsFixed(0)}%', style: theme.textTheme.bodySmall),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(value: _progress),
                            const SizedBox(height: 12),
                          ],
                          if (_verifying) ...[
                            Text('Проверка целостности...', style: theme.textTheme.bodySmall),
                            const SizedBox(height: 8),
                            const LinearProgressIndicator(),
                            const SizedBox(height: 12),
                          ],
                          if (_installing) ...[
                            Text('Запрос на установку...', style: theme.textTheme.bodySmall),
                            const SizedBox(height: 8),
                            const LinearProgressIndicator(),
                            const SizedBox(height: 12),
                          ],
                          Row(children: [
                            Expanded(
                              child: TextButton(
                                onPressed: forced ? null : () => Navigator.of(context).pop(),
                                child: Text(forced ? 'Обновление обязательно' : 'Позже'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: (_downloading || _installing || _verifying) ? null : _startDownload,
                                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                child: Text(_downloading ? 'Скачивается...' : (_installing ? 'Устанавливается...' : 'Обновить')),
                              ),
                            ),
                          ])
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
