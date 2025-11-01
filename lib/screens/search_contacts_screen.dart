import 'package:flutter/material.dart';
import 'package:two_space_app/services/appwrite_service.dart';
import 'package:appwrite/appwrite.dart';
import 'package:two_space_app/widgets/user_avatar.dart';
import 'dart:async';

import 'package:two_space_app/services/settings_service.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

class SearchContactsScreen extends StatefulWidget {
  const SearchContactsScreen({super.key});

  @override
  State<SearchContactsScreen> createState() => _SearchContactsScreenState();
}


class _SearchContactsScreenState extends State<SearchContactsScreen> {
  // Helper: ensure authenticated before performing sensitive actions
  Future<bool> withAuth(Future<void> Function() action) async {
    try {
      final client = AppwriteService.client;
      if (client == null) {
        // No client configured, redirect to login
        if (mounted) Navigator.of(context).pushReplacementNamed('/login');
        return false;
      }
      final account = Account(client);
      // Check if current session is valid
      try {
        await account.get();
      } catch (e) {
        // Not authenticated
        if (mounted) Navigator.of(context).pushReplacementNamed('/login');
                  return false;
      }
      // Ensure we have a JWT set on the client for server-side calls
      try {
        final resp = await account.createJWT();
        // resp might be Map-like or a model with .jwt
        String? jwt;
        final dynamic r = resp;
        if (r is Map) {
          jwt = (r['jwt'] ?? r['token'] ?? (r['data'] is Map ? r['data']['jwt'] : null))?.toString();
        } else {
          try {
            jwt = (r.jwt as String?);
          } catch (_) {
            jwt = null;
          }
        }
        if (jwt != null && jwt.isNotEmpty) {
          try {
            client.setJWT(jwt);
          } catch (_) {}
        }
      } catch (_) {
        // ignore JWT creation errors - not fatal for client operations
      }
      await action();
      return true;
    } catch (e) {
      if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка аутентификации: $e'))));
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
      // Try searching directly first; AppwriteService.searchUsers will attempt
      // to use available authentication (JWT/cookie) or API key fallback.
      try {
        final res = await AppwriteService.searchUsers(q, limit: 6);
        if (mounted) setState(() => _results = List<Map<String, dynamic>>.from(res));
      } catch (err) {
        final text = err.toString();
        // If search failed due to missing authentication, try acquiring JWT and retry.
        if (text.contains('no authentication available') || text.toLowerCase().contains('401')) {
          final ok = await withAuth(() async {
            final res = await AppwriteService.searchUsers(q, limit: 6);
            if (mounted) setState(() => _results = List<Map<String, dynamic>>.from(res));
          });
          if (!ok) throw Exception('not authenticated');
        } else {
          rethrow;
        }
      }
    } catch (e) {
      final text = e.toString();
      if (text.contains('no authentication available') || text.toLowerCase().contains('not authenticated') || text.toLowerCase().contains('401')) {
        // Prompt user to login since search requires authentication or API key
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final res = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Требуется вход'),
                content: const Text('Для поиска контактов необходим вход в аккаунт. Хотите перейти на экран входа?'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
                  ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Войти')),
                ],
              ),
            );
            if (res == true) Navigator.of(context).pushReplacementNamed('/login');
          });
        }
      } else {
        if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка поиска: $e'))));
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
        padding: const EdgeInsets.all(12.0),
          child: Column(children: [
          // Modern rounded search bar
          Row(children: [
            Expanded(
              child: ValueListenableBuilder<bool>(
                valueListenable: SettingsService.paleVioletNotifier,
                builder: (context, pale, _) {
                  return Container(
                    decoration: BoxDecoration(
                      color: pale ? const Color(0xFFF6F0FF) : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Theme.of(context).shadowColor.withOpacity(0.03), blurRadius: 6)],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Builder(builder: (ctx) {
                      final iconColor = SettingsService.paleVioletNotifier.value ? const Color(0xFF6B46C1) : Theme.of(ctx).iconTheme.color ?? Colors.grey;
                      return TextField(
                        controller: _ctrl,
                        style: Theme.of(ctx).textTheme.bodyLarge,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          prefixIconColor: iconColor,
                          hintText: 'Никнейм или номер телефона',
                          hintStyle: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: iconColor.withOpacity(0.6)),
                          border: InputBorder.none,
                          suffixIcon: _ctrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () { setState(() { _ctrl.clear(); _results = []; }); }) : null,
                        ),
                        onChanged: (_) {
                          setState(() => _showCancel = _ctrl.text.isNotEmpty);
                          _debounce?.cancel();
                          _debounce = Timer(const Duration(milliseconds: 350), () => _search());
                        },
                      );
                    }),
                  );
                },
              ),
            ),
            if (_showCancel) ...[
              const SizedBox(width: 8),
              TextButton(onPressed: () { setState(() { _ctrl.clear(); _results = []; _showCancel = false; }); }, child: const Text('Отмена'))
            ]
          ]),
          const SizedBox(height: 12),
          const SizedBox(height: 8),
          Expanded(
            child: _loading && _results.isEmpty
                ? ListView.separated(
                    itemCount: 4,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (c, i) {
                      final base = Theme.of(context).colorScheme.surfaceVariant;
                      final highlight = Theme.of(context).colorScheme.onSurface.withOpacity(0.06);
                      return Shimmer.fromColors(
                        baseColor: base,
                        highlightColor: Color.lerp(base, highlight, 0.6)!,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
                          child: Row(children: [
                            Container(width: 52, height: 52, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Container(height: 14, width: double.infinity, color: Colors.white),
                                const SizedBox(height: 8),
                                Container(height: 12, width: 120, color: Colors.white),
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
                    separatorBuilder: (_, __) => const Divider(height: 1),
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
                        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              final peerId = (e['\$id'] ?? e['id'])?.toString() ?? '';
                              if (peerId.isEmpty) throw Exception('invalid peer id');
                              if (!mounted) return;
                              // Return selected peerId to caller so home can open/create the chat.
                              Navigator.of(context).pop(peerId);
                            } catch (err) {
                              if (!mounted) return;
                              messenger.showSnackBar(SnackBar(content: Text('Не удалось выбрать контакт: ${AppwriteService.readableError(err)}')));
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(children: [
                              UserAvatar(avatarUrl: avatar, radius: 26),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name.toString(), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 6),
                                    Row(children: [
                                      if (nickname != null && nickname.isNotEmpty) Text('@$nickname', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7))),
                                      if (nickname != null && nickname.isNotEmpty) const SizedBox(width: 8),
                                      Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7))),
                                      const Spacer(),
                                      prefs['online'] == true ? Icon(Icons.circle, size: 10, color: Colors.green.shade400) : Icon(Icons.access_time, size: 12, color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6)),
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
        ]),
      ),
    );
  }
}
