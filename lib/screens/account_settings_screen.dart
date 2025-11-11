import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:two_space_app/models/user.dart';
import 'package:two_space_app/services/appwrite_service.dart';
import 'package:two_space_app/widgets/user_avatar.dart';
import 'package:two_space_app/services/update_service.dart';
import 'package:two_space_app/services/settings_service.dart';
import 'package:shimmer/shimmer.dart';
import 'package:two_space_app/screens/update_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:two_space_app/config/ui_tokens.dart';

/// Clean account settings screen
class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});
  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _nicknameController = TextEditingController();

  String? _avatarUrl;
  String? _avatarFileId;
  List<int>? _avatarBytes;
  // Nickname check state
  Timer? _nickDebounce;
  bool _nickChecking = false;
  String? _nickStatus; // 'ok', 'taken', 'error'
  bool _loading = false;
  String _appVersion = '';
  String _deviceAbi = '';

  @override
  void initState() {
    super.initState();
    _loadAccount();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersion = '${info.version}+${info.buildNumber}');
      // Detect device ABI for display
      try {
        final dip = DeviceInfoPlugin();
        if (Platform.isAndroid) {
          final and = await dip.androidInfo;
          // androidInfo.supportedAbis is List<String>
          final abis = and.supportedAbis.cast<String>();
          if (abis.isNotEmpty) setState(() => _deviceAbi = abis.first);
        } else if (Platform.isIOS) {
          final ios = await dip.iosInfo;
          setState(() => _deviceAbi = ios.utsname.machine);
        }
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _loadAccount() async {
    try {
      final account = await AppwriteService.getAccount();
      if (!mounted) return;
      
      final user = User.fromJson(account);
      _firstNameController.text = user.prefs['firstName'] ?? '';
      _lastNameController.text = user.prefs['lastName'] ?? '';
      _descriptionController.text = user.prefs['description'] ?? '';
      _nicknameController.text = user.prefs['nickname']?.toString().replaceAll('@', '') ?? '';
      _avatarUrl = user.prefs['avatarUrl'];
      _avatarFileId = user.prefs['avatarId'];
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки данных: ${AppwriteService.readableError(e)}')),
        );
      }
    }
    // Try to load cached profile first for instant UI responsiveness.
    try {
      final cached = await SettingsService.readCachedProfile();
      if (cached != null) {
        // Apply cached data to UI immediately
        final fullName = (cached['name'] as String?) ?? '';
        final parts = fullName.split(' ');
        if (mounted) {
          setState(() {
            _firstNameController.text = parts.isNotEmpty ? parts.first : '';
            _lastNameController.text = parts.length > 1 ? parts.sublist(1).join(' ') : '';
            final prefs = (cached['prefs'] is Map) ? Map<String, dynamic>.from(cached['prefs'] as Map) : <String, dynamic>{};
            _descriptionController.text = prefs['description'] as String? ?? '';
            _nicknameController.text = ((prefs['nickname'] as String?) ?? '').replaceAll('@', '');
            // Phone is edited from the Privacy screen (separate flow). Do not populate local phone field here.
            _avatarUrl = (prefs['avatarUrl'] as String?) ?? (cached['avatar'] as String?);
          });
        }
      }
    } catch (_) {}

    setState(() => _loading = true);
    try {
      final account = await AppwriteService.getAccount();
      // account fields: name, email, prefs, phone, etc.
      try {
        // account['email'] available if needed in the future
      } catch (_) {}
      final fullName = account['name'] as String? ?? '';
      // split to first/last if needed
      final parts = fullName.split(' ');
      _firstNameController.text = parts.isNotEmpty ? parts.first : '';
      _lastNameController.text = parts.length > 1 ? parts.sublist(1).join(' ') : '';
  final prefs = (account['prefs'] is Map) ? Map<String, dynamic>.from(account['prefs'] as Map) : <String, dynamic>{};
  _descriptionController.text = prefs['description'] as String? ?? '';
  _nicknameController.text = ((prefs['nickname'] as String?) ?? '').replaceAll('@', '');
  // Prefer server-stored phone (Account.phone) which is the official phone field in Appwrite
  String phoneVal = '';
  try {
    final acctPhone = account['phone'];
    if (acctPhone is String) {
      phoneVal = acctPhone;
    } else if (acctPhone is Map) {
      // Some variants may return a map - try common keys
      phoneVal = (acctPhone['phone'] ?? acctPhone['number'] ?? acctPhone['value'])?.toString() ?? '';
    }
  } catch (_) {}
  if (phoneVal.isEmpty) {
    phoneVal = prefs['phone'] as String? ?? '';
  }
  // Phone is managed in Privacy -> change phone screen; do not set local phone controller here.
      // Determine avatar URL: prefer prefs.avatarUrl (may already be a view URL),
      // otherwise if account['avatar'] contains a file id or partial value, try to construct view url.
  String? avatar;
  String? avatarFileId;
      try {
        avatar = prefs['avatarUrl'] as String?;
        avatarFileId = prefs['avatarFileId'] as String?;
      } catch (_) {}
      if (avatar == null || avatar.isEmpty) {
        final acctAvatar = account['avatar'];
        if (acctAvatar is String && acctAvatar.isNotEmpty) {
          // If it looks like a url, use it
          if (acctAvatar.startsWith('http')) {
            avatar = acctAvatar;
          } else {
            // treat as file id and build view URL
            try {
              avatar = AppwriteService.getFileViewUrl(acctAvatar).toString();
            } catch (_) {}
          }
        }
      }
      if (mounted) {
        setState(() {
          _avatarUrl = avatar;
          _avatarFileId = avatarFileId;
        });
      }

      // Save full account payload to cache for faster subsequent opens
      try {
        await SettingsService.saveCachedProfile(account as Map<String, dynamic>);
      } catch (_) {}

      // If server provided a file id for the avatar, try to fetch bytes so
      // we can display the image even when the storage bucket is private.
      if (avatarFileId != null && avatarFileId.isNotEmpty) {
        try {
          final bytes = await AppwriteService.getFileBytes(avatarFileId);
          if (bytes.isNotEmpty) {
                  if (mounted) {
                    setState(() => _avatarBytes = bytes);
                  }
          }
        } catch (_) {
          // ignore fetch errors; UI will fall back to avatarUrl if available
        }
      }
      } catch (e) {
      debugPrint('Load account failed: $e');
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(SnackBar(content: Text('Не удалось загрузить аккаунт: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1600);
    if (picked == null) {
      return;
    }
    // Load bytes for cropping
    final bytes = await picked.readAsBytes();
    final cropController = CropController();
    String? croppedTempPath;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(8),
          child: SizedBox(
            width: double.infinity,
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Column(
              children: [
                Expanded(
                  child: Crop(
                    image: bytes,
                    controller: cropController,
                    withCircleUi: false,
                    aspectRatio: 1.0,
                    onCropped: (croppedData) async {
                      final navigator = Navigator.of(ctx);
                      try {
                        final dyn = croppedData as dynamic;
                        List<int> outBytes = <int>[];
                        if (dyn is Uint8List) {
                          outBytes = dyn.toList();
                        } else if (dyn is List<int>) {
                          outBytes = dyn;
                        } else {
                          try {
                            if (dyn.bytes != null) {
                              outBytes = List<int>.from(dyn.bytes as Iterable);
                            } else if (dyn.data != null) {
                              outBytes = List<int>.from(dyn.data as Iterable);
                            }
                          } catch (_) {}
                        }

                        if (outBytes.isNotEmpty) {
                          final tempDir = await getTemporaryDirectory();
                          final tmp = File('${tempDir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.png');
                          await tmp.writeAsBytes(outBytes);
                          croppedTempPath = tmp.path;
                          if (mounted) {
                            setState(() {
                              _avatarBytes = outBytes;
                            });
                          }
                        }
                      } catch (_) {
                        // ignore and fall back to original image if anything fails
                      }
                      navigator.pop();
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
                    TextButton(onPressed: () => cropController.crop(), child: const Text('Готово')),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

  final toUploadPath = croppedTempPath ?? picked.path;
  if (!mounted) return;
  setState(() => _loading = true);
    try {
      dynamic res;
      // Prefer uploading the temp file produced by the cropper (more reliable across platforms).
      if (toUploadPath.isNotEmpty) {
        res = await AppwriteService.uploadAvatar(toUploadPath);
      } else if (_avatarBytes != null && _avatarBytes!.isNotEmpty) {
        res = await AppwriteService.uploadAvatarFromBytes(_avatarBytes!, filename: 'avatar.png');
      } else {
        res = await AppwriteService.uploadAvatar(picked.path);
      }
      final fileId = res['fileId']?.toString();
      // Reload account and attempt to fetch bytes for immediate display
      await _loadAccount();
      if (fileId != null) {
        try {
          final bytes = await AppwriteService.getFileBytes(fileId);
          if (!mounted) return;
          if (bytes.isNotEmpty) {
            setState(() => _avatarBytes = bytes);
          }
        } catch (_) {}
      }
  if (!mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Аватарка обновлена')));
    } catch (e) {
      debugPrint('Avatar upload failed: $e');
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(SnackBar(content: Text('Ошибка загрузки фото: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _loading = true);
    try {
      final first = _firstNameController.text.trim();
      final last = _lastNameController.text.trim();
      final displayName = (first + (last.isNotEmpty ? ' $last' : '')).trim();
      // Fetch current account once to get current prefs and phone
      final currentAccount = await AppwriteService.getAccount();
      final currentPrefs = (currentAccount['prefs'] is Map) ? Map<String, dynamic>.from(currentAccount['prefs'] as Map) : <String, dynamic>{};

      // Phone updates moved to a dedicated screen under Приватность (Change Phone).

      // Now update name + merged prefs (ensure description is preserved)
      final desc = _descriptionController.text.trim();
      // Handle nickname change: attempt to reserve if user changed it
      final nickVal = _nicknameController.text.trim().replaceAll('@', '').toLowerCase();
      final currentNick = (currentPrefs['nickname'] as String?)?.replaceAll('@', '').toLowerCase() ?? '';
      if (nickVal.isNotEmpty && nickVal != currentNick) {
        // If our live check previously determined nickname is taken, abort and notify.
        if (_nickStatus == 'taken') {
          if (mounted) {
            final messenger = ScaffoldMessenger.of(context);
            messenger.showSnackBar(const SnackBar(content: Text('Никнейм занят. Выберите другой.')));
          }
          return;
        }
        try {
          // Reserve (persist) nickname on save only
          await AppwriteService.reserveNickname(nickVal);
          // reserveNickname updates account prefs on success
        } catch (e) {
          if (mounted) {
            final messenger = ScaffoldMessenger.of(context);
            messenger.showSnackBar(SnackBar(content: Text('Не удалось зарезервировать ник: ${AppwriteService.readableError(e)}')));
          }
        }
      }

      final mergedPrefs = {...currentPrefs, 'description': desc};
      if (displayName.isNotEmpty) {
        await AppwriteService.updateAccount(name: displayName, prefs: mergedPrefs);
      } else {
        await AppwriteService.updateAccount(prefs: mergedPrefs);
      }

  await _loadAccount();
  if (!mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Профиль сохранён')));
    } catch (e) {
      debugPrint('Save profile error: $e');
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _onNicknameChanged(String v) {
    _nickDebounce?.cancel();
    setState(() {
      _nickStatus = null;
    });
    _nickDebounce = Timer(const Duration(milliseconds: 500), () => _checkNicknameAvailability(v));
  }

  // Live availability check. Uses searchUsers to avoid reserving on every keystroke.
  Future<void> _checkNicknameAvailability(String raw) async {
    final val = raw.trim().replaceAll('@', '').toLowerCase();
    if (val.isEmpty) return;
    setState(() {
      _nickChecking = true;
      _nickStatus = null;
    });
    try {
      // Try server-side search for the nickname. If no other user has it -> available.
      final results = await AppwriteService.searchUsers(val, limit: 5);
      final me = await AppwriteService.getCurrentUserId();
      bool taken = false;
      for (final r in results) {
        try {
          final id = (r['id'] ?? r['\$id'] ?? r['\$id'])?.toString();
          String nick = '';
          if (r is Map && r['prefs'] is Map) {
            nick = (r['prefs']['nickname'] as String?) ?? '';
            if (nick.startsWith('@')) nick = nick.substring(1);
          }
          // consider match by nickname or by direct equality in returned user id
          if (id != null && id.isNotEmpty && id != me) {
            if (nick.isNotEmpty) {
              if (nick.toLowerCase() == val) {
                taken = true;
                break;
              }
            }
            // also check name field fallback
            final name = (r['name'] as String?) ?? '';
            if (name.toLowerCase() == val) {
              taken = true;
              break;
            }
          }
        } catch (_) {}
      }
      if (taken) {
        setState(() => _nickStatus = 'taken');
      } else {
        setState(() => _nickStatus = 'ok');
      }
    } catch (e) {
      setState(() => _nickStatus = 'error');
    } finally {
      if (mounted) setState(() => _nickChecking = false);
    }
  }

  Future<void> _checkForUpdates() async {
    if (mounted) setState(() => _loading = true);
    try {
      final info = await UpdateService.checkForUpdate();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      if (info == null) {
        messenger.showSnackBar(const SnackBar(content: Text('Обновлений не найдено')));
      } else {
        // Navigate to full-screen update page
        Navigator.of(context).push(MaterialPageRoute(builder: (c) => UpdateScreen(info: info)));
      }
    } catch (e) {
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(SnackBar(content: Text('Ошибка проверки обновлений: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text('Точно выйти из аккаунта?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Выйти')),
        ],
      ),
    );
    if (ok == true) {
      await AppwriteService.deleteCurrentSession();
      if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
    }
  }

  // Account deletion removed intentionally. Use 'Проверить обновления' to trigger update flow.

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _descriptionController.dispose();
    _nicknameController.dispose();
  // Phone controller removed; phone editing moved to Privacy -> Change Phone
    _nickDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // simplified relevant parts: avatar, fields, save button, logout
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Настройки'),
          bottom: const TabBar(tabs: [Tab(text: 'Профиль'), Tab(text: 'Общие')]),
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.01), end: Offset.zero).animate(animation),
              child: child,
            ),
          ),
          child: _loading
              ? SingleChildScrollView(
                  key: const ValueKey('settings_loading'),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Shimmer.fromColors(
                      baseColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      highlightColor: Color.lerp(Theme.of(context).colorScheme.surfaceContainerHighest, Theme.of(context).colorScheme.onSurface.withAlpha((0.06 * 255).round()), 0.6)!,
                      child: Column(children: [
                        Row(children: [
                          Container(width: 112, height: 112, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(56))),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(height: 14, width: double.infinity, color: Colors.white), const SizedBox(height: 8), Container(height: 12, width: 140, color: Colors.white)])),
                        ]),
                        const SizedBox(height: 18),
                        Container(height: 48, color: Colors.white),
                        const SizedBox(height: 12),
                        Container(height: 48, color: Colors.white),
                        const SizedBox(height: 12),
                        Container(height: 96, color: Colors.white),
                        const SizedBox(height: 12),
                        Container(height: 48, color: Colors.white),
                      ]),
                    ),
                  ]),
                )
              : Column(
                  key: const ValueKey('settings_loaded'),
                  children: [
                    Expanded(
                      child: TabBarView(children: [
                        // Profile tab
                        SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Material(
                                elevation: UITokens.cardElevation,
                                color: Theme.of(context).colorScheme.surface,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UITokens.corner)),
                                child: Padding(
                                  padding: const EdgeInsets.all(UITokens.space),
                                  child: Column(
                                    children: [
                                      Stack(
                                        alignment: Alignment.bottomRight,
                                        children: [
                                          UserAvatar(avatarUrl: _avatarUrl, avatarFileId: _avatarFileId, initials: (() {
                                            final first = _firstNameController.text.trim();
                                            final last = _lastNameController.text.trim();
                                            final a = (first.isNotEmpty ? first[0] : '');
                                            final b = (last.isNotEmpty ? last[0] : '');
                                            final res = (a + b).toUpperCase();
                                            return res.isNotEmpty ? res : null;
                                          })(), fullName: '${_firstNameController.text} ${_lastNameController.text}'.trim(), radius: 56),
                                          Positioned(
                                            right: 0,
                                            bottom: 0,
                                            child: Material(
                                              color: Theme.of(context).colorScheme.primary,
                                              shape: const CircleBorder(),
                                              child: InkWell(
                                                onTap: _pickAndUploadAvatar,
                                                customBorder: const CircleBorder(),
                                                child: const Padding(padding: EdgeInsets.all(8.0), child: Icon(Icons.camera_alt, color: Colors.white, size: 20)),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      if (_nickChecking)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 6.0, left: 2.0),
                                          child: Text('Проверка никнейма...', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withAlpha((0.7 * 255).round()))),
                                        ),
                                      if (!_nickChecking && _nickStatus == 'ok')
                                        Padding(padding: const EdgeInsets.only(top: 6.0, left: 2.0), child: Text('Никнейм свободен', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green))),
                                      const SizedBox(height: 12),
                                      ValueListenableBuilder<bool>(
                                        valueListenable: SettingsService.paleVioletNotifier,
                                        builder: (c, pale, _) {
                                          final base = Theme.of(context).copyWith(
                                            inputDecorationTheme: InputDecorationTheme(
                                              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(UITokens.cornerSm))),
                                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(UITokens.cornerSm))),
                                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(UITokens.cornerSm))),
                                              filled: pale,
                                              fillColor: pale ? const Color(0xFFF6F0FF) : null,
                                            ),
                                          );
                                          return Theme(
                                            data: base,
                                            child: Row(
                                              children: [
                                                Expanded(child: TextField(controller: _firstNameController, maxLength: 30, decoration: const InputDecoration(labelText: 'Имя'))),
                                                const SizedBox(width: 12),
                                                Expanded(child: TextField(controller: _lastNameController, maxLength: 30, decoration: const InputDecoration(labelText: 'Фамилия'))),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      ValueListenableBuilder<bool>(
                                        valueListenable: SettingsService.paleVioletNotifier,
                                        builder: (c2, pale2, _) {
                                          final base = Theme.of(context).copyWith(
                                            inputDecorationTheme: InputDecorationTheme(
                                              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(UITokens.cornerSm))),
                                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(UITokens.cornerSm))),
                                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(UITokens.cornerSm))),
                                              filled: pale2,
                                              fillColor: pale2 ? const Color(0xFFF6F0FF) : null,
                                            ),
                                          );
                                          return Theme(
                                            data: base,
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: TextField(
                                                    controller: _nicknameController,
                                                    decoration: InputDecoration(
                                                      labelText: 'Никнейм (без @)',
                                                      suffixIcon: _nickChecking
                                                          ? SizedBox(width: 24, height: 24, child: Opacity(opacity: 0.36, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).iconTheme.color?.withAlpha((0.7 * 255).round()))))
                                                          : (_nickStatus == 'ok' ? const Icon(Icons.check, color: Colors.green) : (_nickStatus == 'taken' ? const Icon(Icons.close, color: Colors.redAccent) : null)),
                                                    ),
                                                    style: Theme.of(context).textTheme.bodyLarge,
                                                    maxLength: 32,
                                                    onChanged: _onNicknameChanged,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      ValueListenableBuilder<bool>(
                                        valueListenable: SettingsService.paleVioletNotifier,
                                        builder: (c3, pale3, _) {
                                          final base2 = Theme.of(context).copyWith(
                                            inputDecorationTheme: InputDecorationTheme(
                                              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(UITokens.cornerSm))),
                                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(UITokens.cornerSm))),
                                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(UITokens.cornerSm))),
                                              filled: pale3,
                                              fillColor: pale3 ? const Color(0xFFF6F0FF) : null,
                                            ),
                                          );
                                          return Theme(
                                            data: base2,
                                            child: TextField(controller: _descriptionController, decoration: const InputDecoration(labelText: 'Описание'), style: Theme.of(context).textTheme.bodyLarge, maxLines: 4, maxLength: 200),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: _saveProfile,
                                          icon: const Icon(Icons.save_rounded),
                                          label: const Padding(padding: EdgeInsets.symmetric(vertical: 12.0), child: Text('Сохранить', style: TextStyle(fontSize: 16))),
                                          style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Material(
                                color: Theme.of(context).colorScheme.surface,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UITokens.corner)),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(UITokens.corner),
                                  onTap: () => Navigator.of(context).pushNamed('/change_email'),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    child: Row(children: [const Icon(Icons.email), const SizedBox(width: 12), Expanded(child: Text('Изменить почту', style: Theme.of(context).textTheme.titleMedium)), const Icon(Icons.chevron_right)]),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Material(
                                color: Theme.of(context).colorScheme.surface,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UITokens.corner)),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(UITokens.corner),
                                  onTap: () => Navigator.of(context).pushNamed('/change_phone'),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    child: Row(children: [const Icon(Icons.phone), const SizedBox(width: 12), Expanded(child: Text('Изменить номер телефона', style: Theme.of(context).textTheme.titleMedium)), const Icon(Icons.chevron_right)]),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // General tab
                        SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          ValueListenableBuilder<bool>(valueListenable: SettingsService.chatListOnRightNotifier, builder: (c, val, _) => SwitchListTile(title: const Text('Переместить список чатов направо'), value: val, onChanged: (v) => SettingsService.setChatListOnRight(v))),
                          const SizedBox(height: 8),
                          ValueListenableBuilder<bool>(valueListenable: SettingsService.showEmailNotifier, builder: (c, val, _) => SwitchListTile(title: const Text('Показывать email в профиле'), value: val, onChanged: (v) => SettingsService.setShowEmail(v))),
                          const SizedBox(height: 8),
                          ValueListenableBuilder<bool>(valueListenable: SettingsService.showPhoneNotifier, builder: (c, val, _) => SwitchListTile(title: const Text('Показывать телефон в профиле'), value: val, onChanged: (v) => SettingsService.setShowPhone(v))),
                          const SizedBox(height: 12),
                          const SizedBox(height: 12),
                          Material(
                            color: Theme.of(context).colorScheme.surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UITokens.corner)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(UITokens.corner),
                              onTap: () => Navigator.of(context).pushNamed('/customization'),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                child: Row(
                                  children: [
                                    const Icon(Icons.format_paint),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text('Кастомизация', style: Theme.of(context).textTheme.titleMedium)),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Material(
                            color: Theme.of(context).colorScheme.surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UITokens.corner)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(UITokens.corner),
                              onTap: () => Navigator.of(context).pushNamed('/privacy'),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                child: Row(
                                  children: [
                                    const Icon(Icons.privacy_tip),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text('Приватность', style: Theme.of(context).textTheme.titleMedium)),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Material(
                            color: Theme.of(context).colorScheme.surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UITokens.corner)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(UITokens.corner),
                              onTap: _confirmLogout,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                child: Row(
                                  children: [
                                    const Icon(Icons.logout),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text('Выйти из аккаунта', style: Theme.of(context).textTheme.titleMedium)),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ])),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Center(child: TextButton.icon(onPressed: _checkForUpdates, icon: const Icon(Icons.system_update, color: Colors.white), label: Text('Проверить обновления', style: Theme.of(context).textTheme.titleMedium), style: TextButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.surface, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)))),
                    const SizedBox(height: 18),
                    Center(child: Column(children: [Text('TwoSpace — лёгкий мессенджер для приватного общения нового уровня', style: Theme.of(context).textTheme.bodyMedium), const SizedBox(height: 6), Row(children: [Text('Версия: $_appVersion', style: Theme.of(context).textTheme.bodySmall), const SizedBox(width: 10), if (_deviceAbi.isNotEmpty) Text('Архитектура: $_deviceAbi', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withAlpha((0.7 * 255).round()))),]), const SizedBox(height: 4), Text('Для вопросов и багов: vaksedon@gmail.com', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha((0.8 * 255).round()))),])),
                  ],
                ),
        ),
      ),
    );
  }
}
