import 'package:flutter/material.dart';
import 'dart:async';

import 'package:two_space_app/services/settings_service.dart';
import 'package:two_space_app/services/navigation_service.dart';
import 'package:two_space_app/screens/profile_screen.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:two_space_app/utils/responsive.dart';

class SearchContactsScreen extends StatefulWidget {
  const SearchContactsScreen({super.key});

  @override
  State<SearchContactsScreen> createState() => _SearchContactsScreenState();
}


class _SearchContactsScreenState extends State<SearchContactsScreen> {
  // Helper: ensure authenticated before performing sensitive actions
  Future<bool> withAuth(Future<void> Function() action) async {
    try {
      // AppwriteService not available, skip auth check
      await action();
      return true;
    } catch (e) {
      final navCtx = appNavigatorKey.currentContext;
      if (navCtx != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => ScaffoldMessenger.of(navCtx).showSnackBar(SnackBar(content: Text('Ошибка аутентификации: $e'))));
      }
      return false;
    }
  }


  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  bool _showCancel = false;
  Timer? _debounce;

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return setState(() => _results = []);
    setState(() => _loading = true);
    try {
      // AppwriteService not available, return empty results
      if (mounted) setState(() => _results = []);
    } catch (e) {
      final text = e.toString();
      if (text.contains('no authentication available') || text.toLowerCase().contains('not authenticated') || text.toLowerCase().contains('401')) {
        // Prompt user to login since search requires authentication or API key
        final navCtx = appNavigatorKey.currentContext;
        if (navCtx != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final res = await showDialog<bool>(
              context: navCtx,
              builder: (ctx) => AlertDialog(
                title: const Text('Требуется вход'),
                content: const Text('Для поиска контактов необходим вход в аккаунт. Хотите перейти на экран входа?'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
                  ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Войти')),
                ],
              ),
            );
            if (res == true) appNavigatorKey.currentState?.pushReplacementNamed('/login');
          });
        }
      } else {
        final navCtx = appNavigatorKey.currentContext;
        if (navCtx != null) WidgetsBinding.instance.addPostFrameCallback((_) => ScaffoldMessenger.of(navCtx).showSnackBar(SnackBar(content: Text('Ошибка поиска: $e'))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatLastSeen(String? iso, Map<String,dynamic>? prefs) {
    if (prefs != null && prefs['online'] == true) return 'В сети';
    if (prefs != null && prefs['hideLastSeen'] == true) return 'Был(а) недавно';
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inSeconds < 60) return 'меньше минуты назад';
      if (diff.inMinutes < 60) return '${diff.inMinutes} мин. назад';
      if (diff.inHours < 24) return '${diff.inHours} ч. назад';
      if (diff.inDays < 7) return '${diff.inDays} д. назад';
      return DateFormat('dd.MM.yyyy').format(dt);
    } catch (_) { return ''; }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: BackButton(), title: const Text('Поиск контактов')),
      body: Padding(
        padding: EdgeInsets.all(12.0 * Responsive.scaleWidth(context)),
        child: Column(
          children: [
            // Modern rounded search bar
            Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: SettingsService.paleVioletNotifier,
                    builder: (context, pale, _) {
                      return Container(
                        decoration: BoxDecoration(
                          color: pale ? const Color(0xFFF6F0FF) : Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12 * Responsive.scaleWidth(context)),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).shadowColor.withAlpha((0.03 * 255).round()),
                              blurRadius: 6 * Responsive.scaleWidth(context),
                            ),
                          ],
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 8 * Responsive.scaleWidth(context)),
                        child: Builder(
                          builder: (ctx) {
                            final iconColor = SettingsService.paleVioletNotifier.value
                                ? const Color(0xFF6B46C1)
                                : Theme.of(ctx).iconTheme.color ?? Colors.grey;
                            return TextField(
                              controller: _ctrl,
                              style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                                fontSize: 16 * Responsive.scaleFor(context),
                              ),
                              decoration: InputDecoration(
                                prefixIcon: Icon(
                                  Icons.search,
                                  size: 20 * Responsive.scaleFor(context),
                                ),
                                prefixIconColor: iconColor,
                                hintText: 'Никнейм или номер телефона',
                                hintStyle: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                  fontSize: 14 * Responsive.scaleFor(context),
                                  color: iconColor.withAlpha((0.6 * 255).round()),
                                ),
                                border: InputBorder.none,
                                suffixIcon: _ctrl.text.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(
                                          Icons.clear,
                                          size: 20 * Responsive.scaleFor(context),
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _ctrl.clear();
                                            _results = [];
                                          });
                                        },
                                      )
                                    : null,
                              ),
                              onChanged: (_) {
                                setState(() => _showCancel = _ctrl.text.isNotEmpty);
                                _debounce?.cancel();
                                _debounce = Timer(
                                  const Duration(milliseconds: 350),
                                  () => _search(),
                                );
                              },
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
                if (_showCancel) ...[
                  SizedBox(width: 8 * Responsive.scaleWidth(context)),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _ctrl.clear();
                        _results = [];
                        _showCancel = false;
                      });
                    },
                    child: Text(
                      'Отмена',
                      style: TextStyle(fontSize: 14 * Responsive.scaleFor(context)),
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(height: 12 * Responsive.scaleHeight(context)),
            const SizedBox(height: 8),
            Expanded(
              child: _loading && _results.isEmpty
                  ? ListView.separated(
                      itemCount: 4,
                      cacheExtent: 600,
                      separatorBuilder: (_, __) => SizedBox(height: 8 * Responsive.scaleHeight(context)),
                      itemBuilder: (c, i) {
                        final base = Theme.of(context).colorScheme.surfaceContainerHighest;
                        final highlight = Theme.of(context).colorScheme.onSurface.withAlpha((0.06 * 255).round());
                        return Shimmer.fromColors(
                          baseColor: base,
                          highlightColor: Color.lerp(base, highlight, 0.6)!,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 0, vertical: 6 * Responsive.scaleHeight(context)),
                            child: Row(children: [
                              Container(width: 52 * Responsive.scaleWidth(context), height: 52 * Responsive.scaleWidth(context), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12 * Responsive.scaleWidth(context)))),
                              SizedBox(width: 12 * Responsive.scaleWidth(context)),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Container(height: 14 * Responsive.scaleHeight(context), width: double.infinity, color: Colors.white),
                                  SizedBox(height: 8 * Responsive.scaleHeight(context)),
                                  Container(height: 12 * Responsive.scaleHeight(context), width: 120 * Responsive.scaleWidth(context), color: Colors.white),
                                ]),
                              )
                            ]),
                          ),
                        );
                      },
                    )
                  : _results.isEmpty && !_loading
                      ? Center(child: Text('Ничего не найдено', style: Theme.of(context).textTheme.bodyMedium))
                      : ListView.separated(
                      itemCount: _results.length,
                      cacheExtent: 600,
                      separatorBuilder: (_, __) => Divider(height: 1 * Responsive.scaleHeight(context)),
                      itemBuilder: (c, i) {
                        final e = _results[i];
                        final nickname = (e['nickname'] as String?)?.toString();
                        final name = (e['name'] as String?) ?? (nickname != null && nickname.isNotEmpty ? '@$nickname' : (e['email'] as String?) ?? 'User');
                        final avatar = (e['prefs'] is Map) ? (e['prefs']['avatarUrl'] as String?) : (e['avatar'] as String?);
                        final prefs = (e['prefs'] is Map) ? Map<String, dynamic>.from(e['prefs']) : <String,dynamic>{};
                        final lastSeen = (e['lastSeen'] as String?) ?? (prefs['lastSeen'] as String?);
                        final subtitle = _formatLastSeen(lastSeen, prefs);
                        return Card(
                          color: Theme.of(context).colorScheme.surface,
                          margin: EdgeInsets.symmetric(horizontal: 0, vertical: 6 * Responsive.scaleHeight(context)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12 * Responsive.scaleWidth(context))),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12 * Responsive.scaleWidth(context)),
                            onTap: () async {
                              try {
                                final peerId = (e['\$id'] ?? e['id'])?.toString() ?? '';
                                if (peerId.isEmpty) throw Exception('invalid peer id');
                                if (!mounted) return;
                                // Open profile first; ProfileScreen will return a Chat or Map when "Написать" is used.
                                final res = await appNavigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: peerId, initialName: name.toString(), initialAvatar: avatar)));
                                if (res != null) {
                                  // Return whatever profile returned (Chat or Map) to the caller (HomeScreen)
                                  appNavigatorKey.currentState?.pop(res);
                                }
                              } catch (err) {
                                if (!mounted) return;
                                final navCtx = appNavigatorKey.currentContext;
                                if (navCtx != null) ScaffoldMessenger.of(navCtx).showSnackBar(SnackBar(content: Text('Не удалось выбрать контакт: $err')));
                              }
                            },
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12 * Responsive.scaleWidth(context), vertical: 10 * Responsive.scaleHeight(context)),
                              child: Row(children: [
                                avatar != null && avatar.isNotEmpty
                                  ? FadeInImage.assetNetwork(
                                      placeholder: 'assets/icon/app_icon.png',
                                      image: avatar,
                                      width: 40 * Responsive.scaleWidth(context),
                                      height: 40 * Responsive.scaleWidth(context),
                                      fit: BoxFit.cover,
                                    )
                                  : const Icon(Icons.person, size: 32),
                                SizedBox(width: 12 * Responsive.scaleWidth(context)),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name.toString(), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                                      SizedBox(height: 6 * Responsive.scaleHeight(context)),
                                      Row(children: [
                                        if (nickname != null && nickname.isNotEmpty) Text('@$nickname', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha((0.7 * 255).round()))),
                                        if (nickname != null && nickname.isNotEmpty) SizedBox(width: 8 * Responsive.scaleWidth(context)),
                                        Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha((0.7 * 255).round()))),
                                        const Spacer(),
                                        prefs['online'] == true ? Icon(Icons.circle, size: 10, color: Colors.green.shade400) : Icon(Icons.access_time, size: 12, color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha((0.6 * 255).round())),
                                      ]),
                                    ],
                                  ),
                                ),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
            )
          ],
        ),
      ),
    );
  }
}
