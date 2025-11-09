import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/config/ui_tokens.dart';
import 'package:two_space_app/services/chat_service.dart';
import 'package:two_space_app/services/appwrite_service.dart';
import 'package:two_space_app/widgets/user_avatar.dart';
import 'package:two_space_app/widgets/app_logo.dart';
import 'package:two_space_app/services/realtime_service.dart';
import 'package:two_space_app/screens/search_contacts_screen.dart';
import 'package:two_space_app/screens/chat_screen.dart';
import 'package:two_space_app/screens/profile_screen.dart';
import 'package:shimmer/shimmer.dart';
import 'package:appwrite/appwrite.dart';
// removed unused responsive import

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Ensure authenticated before executing sensitive actions
  Future<bool> withAuth(Future<void> Function() action) async {
    try {
      final client = AppwriteService.client;
      if (client == null) {
        if (mounted) Navigator.of(context).pushReplacementNamed('/login');
        return false;
      }
      final account = Account(client);
      try {
        await account.get();
      } catch (e) {
        // SDK account.get failed — try a REST fallback and refresh JWT
        try {
          final acct = await AppwriteService.getAccount();
          if (acct != null) {
            // Try to refresh JWT into SDK and retry once
            try {
              await AppwriteService.refreshJwt();
              await account.get();
            } catch (_) {
              if (mounted) Navigator.of(context).pushReplacementNamed('/login');
              return false;
            }
          } else {
            if (mounted) Navigator.of(context).pushReplacementNamed('/login');
            return false;
          }
        } catch (_) {
          if (mounted) Navigator.of(context).pushReplacementNamed('/login');
          return false;
        }
      }
      try {
        final resp = await account.createJWT();
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
      } catch (_) {}
      await action();
      return true;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка аутентификации: $e')));
      return false;
    }
  }


  late ChatService chatService;
  List<Chat> chats = [];
  List<Chat> filteredChats = [];
  Chat? favoritesChat;
  Chat? _selectedChat;
  // Map chatId -> peer info (displayName, avatarUrl, prefs)
  final Map<String, Map<String, dynamic>> _peerInfo = {};
  bool isLoading = true;
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Initialize Appwrite client only if environment is configured.
    if (Environment.appwritePublicEndpoint.isNotEmpty && Environment.appwriteProjectId.isNotEmpty) {
      // Prefer the centralized Appwrite client so JWT/session is reused.
      // Avoid creating ad-hoc Client() instances which lack authentication and
      // caused `user_jwt_invalid` errors in the past.
      final sdkClient = AppwriteService.client;
      chatService = (sdkClient != null) ? ChatService(client: sdkClient) : ChatService();
      // Load chats only after ensuring authentication
      withAuth(() => _loadChats());
      // Setup realtime to listen for chat updates
      try {
        final realtime = RealtimeService(AppwriteService.client!);
        realtime.onChatUpdated.listen((doc) {
            try {
            final map = doc.data;
            // Replace or insert chat in list
            final updated = Chat.fromMap(map);
            final idx = chats.indexWhere((c) => c.id == updated.id);
            if (idx >= 0) {
              chats[idx] = updated;
            } else {
              chats.insert(0, updated);
            }
            _filterChats();
          } catch (_) {}
        });
      } catch (_) {}
    } else {
      // Appwrite not configured: create a ChatService that will attempt to
      // use the centralized AppwriteService.database when available. This
      // avoids constructing ad-hoc SDK clients without authentication which
      // previously caused "not authorized" errors.
      chatService = ChatService();
      isLoading = false;
    }
  }

  Future<void> _loadChats() async {
    setState(() {
      isLoading = true;
    });
    try {
      chats = await chatService.loadChats();
      // Populate peer info for direct chats so UI can show interlocutor name/avatar
      try {
        await _populatePeerInfo(chats);
      } catch (_) {}
      // Ensure favorites chat exists for current user
      try {
        final userId = await AppwriteService.getCurrentUserId();
        if (userId != null) {
          final fav = await chatService.getOrCreateFavoritesChat(userId);
          favoritesChat = Chat.fromMap(fav);
        }
      } catch (_) {}
      _filterChats();
      // Auto-select first chat for large-screen usage if nothing selected yet
      try {
        if (_selectedChat == null && (favoritesChat != null || filteredChats.isNotEmpty)) {
          setState(() {
            _selectedChat = favoritesChat ?? filteredChats.first;
          });
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('Error loading chats: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка загрузки чатов')),
        );
      }
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _populatePeerInfo(List<Chat> chatsList) async {
    try {
      final me = await AppwriteService.getCurrentUserId();
      if (me == null) return;
      // Collect peer ids for direct chats and fetch them in batched parallel calls
      final peerIds = <String>[];
      final chatToPeer = <String, String>{};
      for (final chat in chatsList) {
        final members = chat.members;
        if (members.length == 2 && members.contains(me)) {
          final peerId = members.firstWhere((m) => m != me);
          peerIds.add(peerId);
          chatToPeer[chat.id] = peerId;
        }
      }
      if (peerIds.isEmpty) return;
      final users = await AppwriteService.getUsersByIds(peerIds);
      for (final u in users) {
        try {
          final id = (u['\$id'] ?? u['id'])?.toString() ?? '';
          final prefs = (u['prefs'] is Map) ? Map<String, dynamic>.from(u['prefs']) : <String, dynamic>{};
          final displayName = (u['name'] as String?)?.isNotEmpty == true ? u['name'] as String : ((prefs['nickname'] as String?) ?? (u['email'] as String?) ?? '');
          final avatar = (prefs['avatarUrl'] as String?) ?? (u['avatar'] as String?);
          // Find all chats that map to this user id
          final chatIds = chatToPeer.entries.where((e) => e.value == id).map((e) => e.key);
          for (final cid in chatIds) {
            _peerInfo[cid] = {'displayName': displayName, 'avatarUrl': avatar, 'prefs': prefs, 'userId': id};
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _filterChats() {
    if (searchQuery.isEmpty) {
      filteredChats = chats;
    } else {
      filteredChats = chats
          .where((chat) => chat.name.toLowerCase().contains(searchQuery.toLowerCase()))
          .toList();
    }
    setState(() {});
  }

  // Search removed from main screen - logo used instead

  String _formatTime(DateTime time) {
    return DateFormat('HH:mm').format(time);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: const [
            AppLogo(large: false),
            SizedBox(width: 8),
            Text('Чаты'),
          ],
        ),
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/settings'),
            icon: const Icon(Icons.settings, color: Colors.white),
            tooltip: 'Настройки',
          ),
        ],
        // compact header - animated logo + title
      ),
    body: LayoutBuilder(builder: (context, constraints) {
      final isTwoPane = constraints.maxWidth >= 900;

      Widget chatListWidget;
      if (isLoading) {
        chatListWidget = ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: 6,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (c, i) {
            final base = Theme.of(context).colorScheme.surfaceContainerHighest;
            final highlight = Theme.of(context).colorScheme.onSurface.withAlpha((0.06 * 255).round());
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: UITokens.space),
              child: Shimmer.fromColors(
                baseColor: base,
                highlightColor: Color.lerp(base, highlight, 0.6)!,
                child: Card(
                  elevation: UITokens.cardElevation,
                  color: Theme.of(context).colorScheme.surface,
                  margin: const EdgeInsets.symmetric(vertical: UITokens.spaceSm),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UITokens.corner)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: UITokens.space, vertical: UITokens.spaceSm),
                    child: Row(children: [
                      Container(width: 52, height: 52, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
                      const SizedBox(width: UITokens.space),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(height: 14, width: double.infinity, color: Colors.white),
                          const SizedBox(height: UITokens.spaceXS),
                          Container(height: 12, width: 180, color: Colors.white),
                        ]),
                      ),
                      const SizedBox(width: UITokens.space),
                      Container(height: 12, width: 36, color: Colors.white),
                    ]),
                  ),
                ),
              ),
            );
          },
        );
      } else {
        chatListWidget = RefreshIndicator(
          onRefresh: _loadChats,
          child: (() {
            final hasChats = (favoritesChat != null) || filteredChats.isNotEmpty;
            if (!hasChats) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 6,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(children: [
                          Text('Пока нет чатов', style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 12),
                          Text('Начните диалог с коллегой или друзьями. Быстро найдите контакты и создайте новый чат.', style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            ElevatedButton.icon(
                              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchContactsScreen())),
                              icon: const Icon(Icons.search),
                              label: const Text('Найти контакт'),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                                onPressed: () async {
                                  // quick create a self-favorites chat
                                  final navigator = Navigator.of(context);
                                  final uid = await AppwriteService.getCurrentUserId();
                                  if (uid != null) {
                                    try {
                                      final created = await chatService.getOrCreateFavoritesChat(uid);
                                      navigator.pushNamed('/chat', arguments: Chat.fromMap(created));
                                    } catch (_) {}
                                  }
                                },
                              icon: const Icon(Icons.star),
                              label: const Text('Избранное'),
                            ),
                          ])
                        ]),
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              itemCount: (favoritesChat != null ? 1 : 0) + filteredChats.length,
              itemBuilder: (context, index) {
                if (favoritesChat != null && index == 0) {
                    final chat = favoritesChat!;
                      final selected = (_selectedChat != null && _selectedChat!.id == chat.id);
                      return Card(
                        elevation: selected ? UITokens.cardElevation + 2 : UITokens.cardElevation,
                        // avoid deprecated withOpacity
                        color: selected ? Theme.of(context).colorScheme.primary.withAlpha((0.06 * 255).round()) : Theme.of(context).colorScheme.surface,
                    margin: const EdgeInsets.symmetric(horizontal: UITokens.space, vertical: UITokens.spaceSm),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UITokens.corner)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(UITokens.corner),
                      onTap: () {
                        if (isTwoPane) {
                          setState(() => _selectedChat = chat);
                        } else {
                          Navigator.pushNamed(context, '/chat', arguments: chat);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: UITokens.space, vertical: UITokens.spaceSm),
                        child: Row(
                          children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(UITokens.corner),
                                  onTap: () async {
                                    final uid = _peerInfo[chat.id]?['userId'] as String?;
                                    if (uid != null && uid.isNotEmpty) {
                                      final navigator = Navigator.of(context);
                                      final isLarge = MediaQuery.of(context).size.width >= 900;
                                      final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: uid, initialName: _peerInfo[chat.id]?['displayName'] as String?, initialAvatar: _peerInfo[chat.id]?['avatarUrl'] as String?)));
                                      // If profile returned a created Chat, select or open it
                                      if (res != null) {
                                        try {
                                          if (!mounted) return;
                                          if (res is Chat) {
                                            if (isLarge) {
                                              setState(() => _selectedChat = res);
                                            } else {
                                              navigator.pushNamed('/chat', arguments: res);
                                            }
                                          } else if (res is Map) {
                                            final c = Chat.fromMap(Map<String, dynamic>.from(res));
                                            if (isLarge) {
                                              setState(() => _selectedChat = c);
                                            } else {
                                              navigator.pushNamed('/chat', arguments: c);
                                            }
                                          }
                                        } catch (_) {}
                                      }
                                    }
                                  },
                                  child: UserAvatar(
                                    avatarUrl: _peerInfo[chat.id]?['avatarUrl'] ?? chat.avatarUrl,
                                    initials: (() {
                                      final nameForInitials = (_peerInfo[chat.id]?['displayName'] as String?) ?? chat.name;
                                      final parts = nameForInitials.trim().split(RegExp(r'\s+'))..removeWhere((s) => s.isNotEmpty);
                                      if (parts.isEmpty) return '?';
                                      final a = parts[0].isNotEmpty ? parts[0][0] : '';
                                      final b = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
                                      final res = (a + b).toUpperCase();
                                      return res.isNotEmpty ? res : '?';
                                    })(),
                                    fullName: _peerInfo[chat.id]?['displayName'] ?? chat.name,
                                    radius: 26,
                                  ),
                                ),
                            const SizedBox(width: UITokens.space),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          InkWell(
                                            onTap: () async {
                                              final uid = _peerInfo[chat.id]?['userId'] as String?;
                                              if (uid != null && uid.isNotEmpty) {
                                                final navigator = Navigator.of(context);
                                                final isLarge = MediaQuery.of(context).size.width >= 900;
                                                final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: uid, initialName: _peerInfo[chat.id]?['displayName'] as String?, initialAvatar: _peerInfo[chat.id]?['avatarUrl'] as String?)));
                                                if (res != null) {
                                                  try {
                                                    if (!mounted) return;
                                                    if (res is Chat) {
                                                      if (isLarge) {
                                                        setState(() => _selectedChat = res);
                                                      } else {
                                                        navigator.pushNamed('/chat', arguments: res);
                                                      }
                                                    } else if (res is Map) {
                                                      final c = Chat.fromMap(Map<String, dynamic>.from(res));
                                                      if (isLarge) {
                                                        setState(() => _selectedChat = c);
                                                      } else {
                                                        navigator.pushNamed('/chat', arguments: c);
                                                      }
                                                    }
                                                  } catch (_) {}
                                                }
                                              }
                                            },
                                            child: Text(chat.name, style: UITokens.emphasized(context)),
                                          ),
                                          const SizedBox(height: UITokens.spaceXS),
                                          Text(chat.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
                                        ],
                                      ),
                                    ),
                                    PopupMenuButton<int>(
                                      onSelected: (v) {
                                        if (v == 1) {
                                          final uid = _peerInfo[chat.id]?['userId'] as String?;
                                          if (uid != null && uid.isNotEmpty) {
                                            Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: uid, initialName: _peerInfo[chat.id]?['displayName'] as String?, initialAvatar: _peerInfo[chat.id]?['avatarUrl'] as String?)));
                                          }
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(value: 1, child: Text('Профиль')),
                                      ],
                                    ),
                            const SizedBox(width: UITokens.space),
                            Text(_formatTime(chat.lastMessageTime), style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                    final chat = filteredChats[favoritesChat != null ? index - 1 : index];
                        final selected = (_selectedChat != null && _selectedChat!.id == chat.id);
                        return Card(
                          elevation: selected ? UITokens.cardElevation + 2 : UITokens.cardElevation,
                          // avoid deprecated withOpacity
                          color: selected ? Theme.of(context).colorScheme.primary.withAlpha((0.06 * 255).round()) : Theme.of(context).colorScheme.surface,
                  margin: const EdgeInsets.symmetric(horizontal: UITokens.space, vertical: UITokens.spaceSm),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UITokens.corner)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(UITokens.corner),
                    onTap: () {
                      if (isTwoPane) {
                        setState(() => _selectedChat = chat);
                      } else {
                        Navigator.pushNamed(context, '/chat', arguments: chat);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: UITokens.space, vertical: UITokens.spaceSm),
                      child: Row(
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(UITokens.corner),
                            onTap: () {
                              final uid = _peerInfo[chat.id]?['userId'] as String?;
                              if (uid != null && uid.isNotEmpty) {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: uid, initialName: _peerInfo[chat.id]?['displayName'] as String?, initialAvatar: _peerInfo[chat.id]?['avatarUrl'] as String?)));
                              }
                            },
                            child: UserAvatar(
                              avatarUrl: chat.avatarUrl,
                              initials: (() {
                                final parts = chat.name.trim().split(RegExp(r'\s+'))..removeWhere((s) => s.isNotEmpty);
                                if (parts.isEmpty) return '?';
                                final a = parts[0].isNotEmpty ? parts[0][0] : '';
                                final b = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
                                final res = (a + b).toUpperCase();
                                return res.isNotEmpty ? res : '?';
                              })(),
                              fullName: chat.name,
                              radius: 26,
                            ),
                          ),
                          const SizedBox(width: UITokens.space),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  onTap: () {
                                    final uid = _peerInfo[chat.id]?['userId'] as String?;
                                    if (uid != null && uid.isNotEmpty) {
                                      Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: uid, initialName: _peerInfo[chat.id]?['displayName'] as String?, initialAvatar: _peerInfo[chat.id]?['avatarUrl'] as String?)));
                                    }
                                  },
                                  child: Text(_peerInfo[chat.id]?['displayName'] ?? chat.name, style: UITokens.emphasized(context)),
                                ),
                                const SizedBox(height: UITokens.spaceXS),
                                Text(chat.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
                              ],
                            ),
                          ),
                          PopupMenuButton<int>(
                            onSelected: (v) {
                              if (v == 1) {
                                final uid = _peerInfo[chat.id]?['userId'] as String?;
                                if (uid != null && uid.isNotEmpty) {
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: uid, initialName: _peerInfo[chat.id]?['displayName'] as String?, initialAvatar: _peerInfo[chat.id]?['avatarUrl'] as String?)));
                                }
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 1, child: Text('Профиль')),
                            ],
                          ),
                          const SizedBox(width: UITokens.space),
                          Text(_formatTime(chat.lastMessageTime), style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          })(),
        );
      }

          // If not two-pane, just return the chat list widget as body
          if (!isTwoPane) {
            return chatListWidget;
          }

          // Two-pane layout: left — list, right — selected chat or placeholder
          return Row(children: [
            Container(
              width: 360,
              color: Theme.of(context).colorScheme.surface,
              child: Column(children: [
                // small search / header inside left panel
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: UITokens.space, vertical: UITokens.spaceSm),
                  child: Row(children: [
                    Expanded(child: Text('Чаты', style: Theme.of(context).textTheme.titleMedium)),
                    IconButton(onPressed: () => Navigator.pushNamed(context, '/settings'), icon: const Icon(Icons.settings)),
                  ]),
                ),
                const Divider(height: 1),
                Expanded(child: chatListWidget),
              ]),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: _selectedChat != null
                    ? ChatScreen(key: ValueKey(_selectedChat!.id), chat: _selectedChat)
                    : Container(
                        key: const ValueKey('placeholder'),
                        child: Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            // avoid deprecated withOpacity
                            Icon(Icons.chat_bubble_outline, size: 64, color: Theme.of(context).colorScheme.onSurface.withAlpha((0.4 * 255).round())),
                            const SizedBox(height: 12),
                            Text('Выберите чат слева', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchContactsScreen())),
                              icon: const Icon(Icons.search),
                              label: const Text('Найти контакт'),
                            ),
                          ]),
                        ),
                      ),
              ),
            ),
          ]);
        }),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Theme.of(context).colorScheme.primary,
        onPressed: () async {
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          final isLarge = MediaQuery.of(context).size.width >= 900;
          final res = await navigator.push<dynamic>(MaterialPageRoute(builder: (_) => const SearchContactsScreen()));
          if (res == null) return;
          try {
            if (res is Chat) {
              final chat = res;
              if (!mounted) return;
              if (isLarge) {
                setState(() => _selectedChat = chat);
              } else {
                navigator.pushNamed('/chat', arguments: chat);
              }
              return;
            }
            if (res is Map) {
              final chat = Chat.fromMap(Map<String, dynamic>.from(res));
              if (!mounted) return;
              if (isLarge) {
                setState(() => _selectedChat = chat);
              } else {
                navigator.pushNamed('/chat', arguments: chat);
              }
              return;
            }
            // Fallback: previous behavior expected a peerId string
            final peerId = res is String ? res : (res.toString());
            if (peerId.isNotEmpty) {
              final m = await chatService.getOrCreateDirectChat(peerId);
              final chat = Chat.fromMap(m);
              if (!mounted) return;
              if (isLarge) {
                setState(() => _selectedChat = chat);
              } else {
                navigator.pushNamed('/chat', arguments: chat);
              }
            }
          } catch (e) {
            if (!mounted) return;
            messenger.showSnackBar(SnackBar(content: Text('Не удалось создать/открыть чат: ${AppwriteService.readableError(e)}')));
          }
        },
        child: const Icon(Icons.chat, color: Colors.white),
      ),
    );
  }
}

// _SelectedChatPlaceholder removed — we now render real ChatScreen in two-pane mode.