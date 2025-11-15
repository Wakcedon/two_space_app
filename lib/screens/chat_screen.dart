import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import '../widgets/media_preview.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';
import 'package:image_picker/image_picker.dart';
import 'package:two_space_app/utils/responsive.dart';
import 'package:file_picker/file_picker.dart';
// share_plus removed in favor of platform channel wrapper (AppwriteService.shareFile)
// gallery_saver removed due to Android build namespace issues; using platform channel save instead
import 'package:permission_handler/permission_handler.dart';
import 'package:appwrite/models.dart' as models;

import 'package:two_space_app/services/chat_service.dart';
import 'package:two_space_app/services/chat_backend.dart';
import 'package:two_space_app/services/chat_backend_factory.dart';
import 'package:two_space_app/services/appwrite_service.dart';
import 'package:two_space_app/services/auth_service.dart';
import 'package:two_space_app/services/realtime_service.dart';
import 'package:two_space_app/services/local_message_store.dart';
import 'package:two_space_app/services/settings_service.dart';
import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/config/ui_tokens.dart';
import 'package:two_space_app/widgets/user_avatar.dart';
import 'package:two_space_app/widgets/media_viewer.dart';
import 'package:two_space_app/widgets/media_player.dart';
import '../utils/secure_store.dart';
import 'package:two_space_app/screens/profile_screen.dart';

class ChatScreen extends StatefulWidget {
  /// peerId — id пользователя, с которым создаётся/открывается чат
  final String? peerId;
  /// Legacy: allow passing a Chat object (from home screen routes). If provided
  /// we'll derive the peerId from the chat members.
  final Chat? chat;
  final String? title;
  final String? avatarUrl;

  const ChatScreen({super.key, this.peerId, this.chat, this.title, this.avatarUrl}) : assert(peerId != null || chat != null, 'peerId or chat must be provided');

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatBackend _chatService;
  RealtimeService? _realtime;
  dynamic _realtimeSub;

  String? _chatId;
  bool _uploading = false;
  double _uploadProgress = 0.0;
  bool _syncing = false;
  List<Message> _messages = [];
  bool _loading = true;
  String? _meId;
  final LocalMessageStore _localStore = LocalMessageStore();
  // Peer presence/info
  Map<String, dynamic>? _peerPrefs;
  String? _peerDisplayName;
  String? _peerAvatarUrl;

  // Информация о файлах для каждого сообщения
  final Map<String, Map<String, dynamic>> _mediaInfo = {};
  


  final TextEditingController _controller = TextEditingController();
  String? _replyToMessageId;
  Message? _replyToMessage;
  XFile? _pendingImage;

  final ScrollController _scrollController = ScrollController();

  StreamSubscription<models.Document>? _messageStreamSub;

  Timer? _retryTimer;
  static const _pendingKey = 'pending_messages_v1';

  @override
  void initState() {
    super.initState();
    _init();
    // Start periodic flush of pending queue every 8 seconds
    _retryTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      await _flushPendingQueue();
    });
  }

  Future<void> _init() async {
    try {
      _meId = await AuthService().getCurrentUserId();
    } catch (_) {}
    // Ensure chat exists (per-user deterministic chat)
    try {
  // init ChatBackend (Appwrite or Matrix) with existing Appwrite client
  // when available so Appwrite-backed implementation can reuse the SDK.
  _chatService = createChatBackend(client: AppwriteService.client);
      // Determine peerId: widget.peerId (preferred) or derive from provided chat
      String peerId = widget.peerId ?? '';
      if ((peerId.isEmpty) && widget.chat != null && _meId != null) {
        try {
          final members = widget.chat!.members;
          final other = members.firstWhere((m) => m != _meId, orElse: () => '');
          peerId = other;
        } catch (_) {}
      }
      if (peerId.isEmpty) throw Exception('peerId not available');
      // If widget.chat was provided and already contains an id, use it as a fast path
      Map<String, dynamic>? doc;
      if (widget.chat != null && (widget.chat!.id).isNotEmpty) {
        try {
          doc = {
            '\$id': widget.chat!.id,
            'members': widget.chat!.members,
            'name': widget.chat!.name,
            'avatarUrl': widget.chat!.avatarUrl,
          };
        } catch (_) {
          doc = null;
        }
      }
      if (doc == null) doc = await _chatService.getOrCreateDirectChat(peerId);
      // Set initial displayName/avatar from provided widget values (fast path)
      if (widget.title != null || (widget.chat != null && widget.chat!.name.isNotEmpty)) {
        final initialName = widget.title ?? (widget.chat != null ? widget.chat!.name : null);
        setState(() {
          _peerDisplayName = initialName;
          _peerAvatarUrl = widget.avatarUrl ?? (widget.chat != null ? widget.chat!.avatarUrl : null);
        });
      }
      // Provide a fallback display name immediately (peer id) then load richer info in background
      if ((_peerDisplayName == null || _peerDisplayName!.isEmpty) && peerId.isNotEmpty) {
        setState(() {
          _peerDisplayName = peerId;
          _peerAvatarUrl = widget.avatarUrl ?? (widget.chat != null ? widget.chat!.avatarUrl : null);
        });
      }
      // load peer info (prefs, avatar, display name) from server in background
      unawaited(_loadPeerInfo(peerId));
      setState(() {
        _chatId = (doc?['\$id'] ?? doc?['id'] ?? doc?['_id'] ?? '').toString();
      });
      // init local store and load local messages first (offline-first)
      await _localStore.init();
      final localList = await _localStore.getMessages(_chatId!);
      setState(() {
        _messages = localList;
        _loading = false;
      });
  // then sync from server and merge
  _syncFromServer();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }

    // Setup realtime if available. For Matrix-enabled mode use Matrix /sync
    // subscription to room events; otherwise fall back to Appwrite realtime.
    try {
      final client = AppwriteService.client;
      if (Environment.useMatrix) {
        _realtime = RealtimeService(null);
        if (_chatId != null && _chatId!.isNotEmpty) {
          _realtimeSub = _realtime!.subscribeRoomMessages(_chatId!);
          _messageStreamSub = _realtime!.onMessageCreated.listen((doc) async {
            try {
              final m = Map<String, dynamic>.from(doc.data);
              m['\$id'] = doc.$id;
              // Only process messages that belong to this chat
              if (m['chatId'] == _chatId) {
                final mm = Message.fromMap(m);
                // Persist to local store and update UI
                await _localStore.upsertMessage(_chatId!, {
                  '\$id': mm.id,
                  'senderId': mm.senderId,
                  'content': mm.content,
                  'time': mm.time.toIso8601String(),
                  'type': mm.type,
                  if (mm.mediaId != null) 'mediaFileId': mm.mediaId,
                  'deliveredTo': mm.deliveredTo,
                  'readBy': mm.readBy,
                  'replyTo': mm.replyTo,
                  'status': 'sent',
                });
                if (mounted) {
                  setState(() {
                    if (!_messages.any((x) => x.id == mm.id)) _messages.insert(0, mm);
                  });
                  if (mm.senderId != _meId) {
                    unawaited(_markAllMessagesRead());
                  }
                }
              }
            } catch (_) {}
          });
        }
      } else if (client != null) {
        _realtime = RealtimeService(client);
        _realtimeSub = _realtime!.subscribeMessages(Environment.appwriteMessagesCollectionId);
        _messageStreamSub = _realtime!.onMessageCreated.listen((doc) async {
          try {
            final m = Map<String, dynamic>.from(doc.data);
            m['\$id'] = doc.$id;
            // Only process messages that belong to this chat
            if (m['chatId'] == _chatId) {
              final mm = Message.fromMap(m);
              // Persist to local store and update UI
              await _localStore.upsertMessage(_chatId!, {
                '\$id': mm.id,
                'senderId': mm.senderId,
                'content': mm.content,
                'time': mm.time.toIso8601String(),
                'type': mm.type,
                if (mm.mediaId != null) 'mediaFileId': mm.mediaId,
                'deliveredTo': mm.deliveredTo,
                'readBy': mm.readBy,
                'replyTo': mm.replyTo,
                'status': 'sent',
              });
              if (mounted) {
                setState(() {
                  if (!_messages.any((x) => x.id == mm.id)) _messages.insert(0, mm);
                });
                  // If the incoming message is from the other user, mark it as read
                  if (mm.senderId != _meId) {
                    unawaited(_markAllMessagesRead());
                  }
              }
            }
          } catch (_) {}
        });
      }
    } catch (_) {}
  }

  Future<void> _loadMessages() async {
    if (_chatId == null) return;
    setState(() => _loading = true);
    try {
      final list = await _chatService.loadMessages(_chatId!);
      setState(() {
        _messages = list;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  /// Sync messages from server into local store and refresh UI.
  Future<void> _syncFromServer() async {
    if (_syncing) return;
    if (_chatId == null) return;
    _syncing = true;
    try {
      final serverList = await _chatService.loadMessages(_chatId!);
      for (final m in serverList) {
        await _localStore.upsertMessage(_chatId!, {
          '\$id': m.id,
          'senderId': m.senderId,
          'content': m.content,
          'time': m.time.toIso8601String(),
          'type': m.type,
          if (m.mediaId != null) 'mediaFileId': m.mediaId,
          'deliveredTo': m.deliveredTo,
          'readBy': m.readBy,
          'replyTo': m.replyTo,
          'status': 'sent',
        });
      }
      final merged = await _localStore.getMessages(_chatId!);
      if (mounted) setState(() {
        _messages = merged;
        _loading = false;
      });
      // Mark messages as read on successful sync
      unawaited(_markAllMessagesRead());
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    } finally {
      _syncing = false;
    }
  }

  /// Mark all messages in the current chat as read for the current user.
  /// Updates server and local store for an immediate UI reflection.
  Future<void> _markAllMessagesRead() async {
    try {
      if (_chatId == null || _meId == null) return;
      for (final m in List<Message>.from(_messages)) {
        try {
          if (m.senderId == _meId) continue; // don't mark own messages
          if (m.readBy.contains(_meId)) continue;
          // Mark on server
          try {
            await _chatService.markRead(m.id, _meId!);
          } catch (_) {
            // ignore server errors, we'll still update local cache
          }
          // Update local store to include our read flag
          final updated = <String, dynamic>{
            '\$id': m.id,
            'senderId': m.senderId,
            'content': m.content,
            'time': m.time.toIso8601String(),
            'type': m.type,
            'readBy': List<String>.from(m.readBy)..add(_meId!),
            'deliveredTo': m.deliveredTo,
            if (m.mediaId != null) 'mediaFileId': m.mediaId,
          };
          await _localStore.upsertMessage(_chatId!, updated);
        } catch (_) {}
      }
      // Refresh UI from local store
      final merged = await _localStore.getMessages(_chatId!);
      if (mounted) setState(() => _messages = merged);
    } catch (_) {}
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    try {
      _messageStreamSub?.cancel();
    } catch (_) {}
    try {
      _realtimeSub?.close();
    } catch (_) {}
    _realtime?.dispose();
    try {
      _localStore.close();
    } catch (_) {}
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPeerInfo(String peerId) async {
    try {
      Map<String, dynamic> u = {};
      if (Environment.useMatrix) {
        try {
          u = await _chatService.getUserInfo(peerId);
        } catch (_) {
          u = {};
        }
      } else {
        try {
          u = await AppwriteService.getUserById(peerId);
        } catch (_) {
          u = {};
        }
      }
      if (u.isNotEmpty) {
        final prefs = (u['prefs'] is Map) ? Map<String, dynamic>.from(u['prefs']) : <String, dynamic>{};
        // Derive display name from several possible fields for robustness
        String displayName = '';
        try {
          final nameValue = u['name'] as String?;
          if (nameValue?.trim().isNotEmpty == true) displayName = nameValue!.trim();
        } catch (_) {}
        try {
          final displayNameValue = u['displayName'] as String?;
          if (displayName.isEmpty && displayNameValue?.trim().isNotEmpty == true) displayName = displayNameValue!.trim();
        } catch (_) {}
        try {
          final nick = prefs['nickname'] as String?;
          if (displayName.isEmpty && nick?.trim().isNotEmpty == true) displayName = nick!.trim();
        } catch (_) {}
        try {
          final email = u['email'] as String?;
          if (displayName.isEmpty && email?.isNotEmpty == true) displayName = email!.split('@').first;
        } catch (_) {}
        if (displayName.isEmpty) displayName = peerId;

        // Derive avatar URL from prefs or common fields
        String? avatar;
        try {
          avatar = (prefs['avatarUrl'] as String?) ?? (prefs['avatar'] as String?);
        } catch (_) {}
        try {
          avatar ??= (u['avatar'] as String?) ?? (u['photo'] as String?) ?? (u['picture'] as String?) ?? (u['avatarUrl'] as String?);
        } catch (_) {}

        if (mounted) setState(() {
          _peerPrefs = prefs;
          _peerDisplayName = displayName;
          _peerAvatarUrl = avatar;
        });
      }
    } catch (_) {}
  }

  String _formatUserStatusFromPrefs(Map<String, dynamic>? prefs) {
    if (prefs == null) return '';
    try {
      if (prefs['online'] == true) return 'В сети';
      if (prefs['hideLastSeen'] == true) return 'Был(а) недавно';
      final lastSeen = prefs['lastSeen'] as String?;
      if (lastSeen == null) return '';
      final dt = DateTime.tryParse(lastSeen)?.toLocal();
      if (dt == null) return '';
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inSeconds < 60) return 'меньше минуты назад';
      if (diff.inMinutes < 60) return '${diff.inMinutes} мин. назад';
      if (diff.inHours < 24) return '${diff.inHours} ч. назад';
      if (diff.inDays < 7) return '${diff.inDays} д. назад';
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    } catch (_) {
      return '';
    }
  }

  Future<void> _pickImage() async {
    try {
      final choice = await showModalBottomSheet<String?>(context: context, builder: (c) {
        return SafeArea(
          child: Wrap(children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Галерея'),
              subtitle: const Text('Фото и видео'),
              onTap: () => Navigator.of(c).pop('gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: const Text('Файл'),
              onTap: () => Navigator.of(c).pop('file'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Отмена'),
              onTap: () => Navigator.of(c).pop(null),
            ),
          ]),
        );
      });

      if (choice == null) return;
      if (!mounted) return;

      if (choice == 'gallery') {
        final picker = ImagePicker();
        final result = await picker.pickMultipleMedia();
        if (result.isEmpty) return;

        if (!mounted) return;
        // Если выбрано несколько файлов, будем отправлять их последовательно
        for (final media in result) {
          if (!mounted) return;
          final mimeType = media.mimeType ?? '';
          if (mimeType.startsWith('image/') || mimeType.startsWith('video/')) {
            setState(() => _pendingImage = media);
            await _sendMessage(); // Отправляем сразу после выбора каждого файла
          }
        }
        if (!mounted) return;
        setState(() => _pendingImage = null);
      } else if (choice == 'file') {
        final res = await FilePicker.platform.pickFiles(
          allowMultiple: false,
          type: FileType.any,
        );
        if (res == null || res.files.isEmpty) return;
        final f = res.files.first;
        if (f.path == null) return;
        if (!mounted) return;
        setState(() => _pendingImage = XFile(f.path!));
      }
    } catch (e) {
      debugPrint('pickImage error: $e');
    }
  }

  Future<void> _enqueuePending(Map<String, dynamic> item) async {
    try {
      final raw = await SecureStore.read(_pendingKey);
      final list = raw != null ? (jsonDecode(raw) as List<dynamic>) : <dynamic>[];
      list.add(item);
      await SecureStore.write(_pendingKey, jsonEncode(list));
    } catch (_) {}
  }

  Future<void> _flushPendingQueue() async {
    try {
      final raw = await SecureStore.read(_pendingKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List<dynamic>).toList();
      if (list.isEmpty) return;
      final remaining = <dynamic>[];
      for (final it in list) {
        try {
          final map = Map<String, dynamic>.from(it as Map);
          final chatId = map['chatId']?.toString();
          if (chatId == null || chatId.isEmpty) continue;
          await AppwriteService.sendMessage(chatId, map['payload'] as Map<String, dynamic>);
        } catch (e) {
          // keep for later
          remaining.add(it);
        }
      }
      if (remaining.isEmpty) {
        await SecureStore.delete(_pendingKey);
      } else {
        await SecureStore.write(_pendingKey, jsonEncode(remaining));
      }
    } catch (_) {}
    // Also try to flush local pending messages stored in sembast
    try {
      if (_chatId != null) {
        final pend = await _localStore.getPendingMessages(_chatId!);
        for (final p in pend) {
          try {
            final localId = (p['\$id'] ?? p['id'])?.toString() ?? '';
            final payload = <String, dynamic>{
              'content': p['content'] ?? '',
              'type': p['type'] ?? 'text',
            };
            if (p['mediaFileId'] != null) payload['mediaFileId'] = p['mediaFileId'];
            if (p['replyTo'] != null) payload['replyTo'] = p['replyTo'];
            final sent = await AppwriteService.sendMessage(_chatId!, payload);
            final sentMap = Map<String, dynamic>.from(sent as Map<String, dynamic>);
            final serverId = (sentMap['\$id'] ?? sentMap['id'])?.toString();
            await _localStore.markMessageSent(_chatId!, localId, serverId: serverId, serverPayload: sentMap);
          } catch (e) {
            // leave for next round
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _sendMessage({String? text}) async {
    if (_chatId == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Чат не готов. Попробуйте позже')));
      return;
    }
    final content = (text ?? _controller.text).trim();
    if ((content.isEmpty) && _pendingImage == null) return;

    setState(() {
      _controller.clear();
    });

    try {
      // Prepare local optimistic message
      final localId = 'local_${DateTime.now().millisecondsSinceEpoch}_${_meId ?? 'me'}';
      String type = 'text';
      String? mediaFileId;
      if (_pendingImage != null) {
        // Upload in background but keep message as pending
        try {
          setState(() {
            _uploading = true;
            _uploadProgress = 0.0;
          });
          final upload = await AppwriteService.uploadFileToStorageWithProgress(
            _pendingImage!.path,
            filename: _pendingImage!.name,
            onProgress: (sent, total) {
              if (mounted) setState(() => _uploadProgress = total > 0 ? sent / total : 0.0);
            },
          );
          mediaFileId = (upload['\$id'] ?? upload['id'])?.toString();
          type = 'image';
        } catch (_) {
          // keep as pending without media id, user can retry
        } finally {
          setState(() {
            _uploading = false;
            _uploadProgress = 0.0;
          });
        }
      }

      final localMessage = {
        '\$id': localId,
        'senderId': _meId ?? '',
        'content': content,
        'time': DateTime.now().toIso8601String(),
        'type': type,
        if (mediaFileId != null) 'mediaFileId': mediaFileId,
        if (_replyToMessageId != null) 'replyTo': _replyToMessageId,
        'status': 'pending',
      };

      // persist locally and show optimistic UI
      await _localStore.upsertMessage(_chatId!, localMessage);
      setState(() {
        try {
          final mm = Message.fromMap(Map<String, dynamic>.from(localMessage));
          _messages.insert(0, mm);
        } catch (_) {}
        _pendingImage = null;
        _replyToMessageId = null;
        _replyToMessage = null;
      });

      _scrollToBottom();

      // Attempt to send to server; if successful replace local record
      try {
        final payload = <String, dynamic>{
          'content': content,
          'type': type,
          if (mediaFileId != null) 'mediaFileId': mediaFileId,
          if (_replyToMessageId != null) 'replyTo': _replyToMessageId,
        };
        final sent = await AppwriteService.sendMessage(_chatId!, payload);
        final sentMap = Map<String, dynamic>.from(sent as Map<String, dynamic>);
        final serverId = (sentMap['\$id'] ?? sentMap['id'])?.toString();
        await _localStore.markMessageSent(_chatId!, localId, serverId: serverId, serverPayload: sentMap);
        // refresh messages in UI (merge)
        final merged = await _localStore.getMessages(_chatId!);
        if (mounted) setState(() => _messages = merged);
      } catch (e) {
        // keep pending; also write to SecureStore as fallback queue
        await _enqueuePending({'chatId': _chatId, 'payload': {'content': content, 'type': type, if (mediaFileId != null) 'mediaFileId': mediaFileId}, 'createdAt': DateTime.now().toIso8601String()});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сообщение поставлено в очередь — отправим при подключении')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: ${AppwriteService.readableError(e)}')));
    }
  }

  // Contact picker for forwarding
  Future<String?> _pickContact() async {
    final selected = await showModalBottomSheet<String?>(context: context, isScrollControlled: true, builder: (c) {
      final ctrl = TextEditingController();
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: StatefulBuilder(builder: (ctx, setLocal) {
          List<dynamic> results = [];
          bool loading = false;
          Future<void> doSearch(String q) async {
            if (q.trim().isEmpty) return;
            setLocal(() => loading = true);
            try {
              final users = await AppwriteService.searchUsers(q, limit: 30);
              setLocal(() => results = users);
            } catch (_) {
              setLocal(() => results = []);
            }
            setLocal(() => loading = false);
          }

          return SizedBox(height: 420, child: Column(children: [
            Padding(padding: const EdgeInsets.all(12), child: Row(children: [
              Expanded(child: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Поиск по нику или имени'))),
              IconButton(icon: const Icon(Icons.search), onPressed: () => doSearch(ctrl.text)),
            ])),
            if (loading) const LinearProgressIndicator(),
            Expanded(child: results.isEmpty ? const Center(child: Text('Ничего не найдено')) : ListView.builder(itemCount: results.length, itemBuilder: (ctx2, i) {
              final u = results[i] as Map<String, dynamic>;
              final name = (u['name'] ?? u['nickname'] ?? '') as String;
              final id = (u['\$id'] ?? u['id'] ?? u['id'])?.toString() ?? '';
              final prefs = (u['prefs'] is Map) ? Map<String, dynamic>.from(u['prefs']) : <String, dynamic>{};
              final avatar = prefs['avatarUrl'] as String?;
              return ListTile(leading: UserAvatar(avatarUrl: avatar, radius: 20), title: Text(name), subtitle: Text(id), onTap: () => Navigator.pop(ctx, id));
            })),
          ]));
        }),
      );
    });
    return selected;
  }

  Future<void> _forwardMessage(Message m) async {
    // open contact picker
    final targetUserId = await _pickContact();
    if (targetUserId == null || targetUserId.isEmpty) return;
    try {
      final targetChat = await _chatService.getOrCreateDirectChat(targetUserId);
      final targetId = (targetChat['\$id'] ?? targetChat['id'] ?? '').toString();
      final payload = {'content': m.content, 'type': m.type, if (m.mediaId != null) 'mediaFileId': m.mediaId, 'forwardedFrom': _meId};
      try {
  await AppwriteService.sendMessage(targetId, payload);
  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Переслано')));
      } catch (e) {
        // enqueue
  await _enqueuePending({'chatId': targetId, 'payload': payload, 'createdAt': DateTime.now().toIso8601String()});
  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Переслано в очередь')));
      }
    } catch (e) {
  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка пересылки: ${AppwriteService.readableError(e)}')));
    }
  }

  void _scrollToBottom() {
    try {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    } catch (_) {}
  }

  void _onLongPressMessage(Message m) {
    showModalBottomSheet(
      context: context,
      builder: (c) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.emoji_emotions),
                title: const Text('Реакция'),
                onTap: () {
                  Navigator.pop(c);
                  _showReactionPicker(m);
                },
              ),
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Ответить'),
                onTap: () {
                  Navigator.pop(c);
                  setState(() {
                    _replyToMessageId = m.id;
                    _replyToMessage = m;
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.forward),
                title: const Text('Переслать'),
                onTap: () {
                  Navigator.pop(c);
                  _forwardMessage(m);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Копировать'),
                onTap: () {
                  Navigator.pop(c);
                  Clipboard.setData(ClipboardData(text: m.content));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопировано')));
                },
              ),
              if (m.mediaId != null) ...[
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Скачать'),
                  onTap: () async {
                    Navigator.pop(c);
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      final path = await AppwriteService.downloadFileToTemp(m.mediaId!, filename: '${m.mediaId}');
                      messenger.showSnackBar(SnackBar(content: Text('Файл сохранён: $path')));
                    } catch (e) {
                      messenger.showSnackBar(SnackBar(content: Text('Ошибка скачивания: ${AppwriteService.readableError(e)}')));
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.save_alt),
                  title: const Text('Сохранить в галерею'),
                  onTap: () async {
                    Navigator.pop(c);
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      // Request permissions first
                      bool granted = false;
                      if (Platform.isAndroid) {
                        if (await Permission.storage.status.isDenied) {
                          // Для Android < 13 используем storage
                          if (await Permission.storage.request().isGranted) {
                            granted = true;
                          }
                        } else if (await Permission.photos.status.isDenied || await Permission.videos.status.isDenied) {
                          // Для Android 13+ используем photos и videos
                          final photos = await Permission.photos.request();
                          final videos = await Permission.videos.request();
                          granted = photos.isGranted && videos.isGranted;
                        } else {
                          granted = true;
                        }
                      } else if (Platform.isIOS) {
                        final photos = await Permission.photos.request();
                        granted = photos.isGranted;
                      } else {
                        granted = true;
                      }
                      if (!granted) {
                        messenger.showSnackBar(const SnackBar(content: Text('Требуются права для сохранения в галерею')));
                        return;
                      }
                      final path = await AppwriteService.downloadFileToTemp(m.mediaId!, filename: '${m.mediaId}');
                      final lower = path.toLowerCase();
                      bool ok = false;
                      if (lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.webm')) {
                        ok = await AppwriteService.saveFileToGallery(path);
                      } else {
                        ok = await AppwriteService.saveFileToGallery(path);
                      }
                      messenger.showSnackBar(SnackBar(content: Text(ok ? 'Сохранено в галерею' : 'Не удалось сохранить')));
                    } catch (e) {
                      messenger.showSnackBar(SnackBar(content: Text('Ошибка: ${AppwriteService.readableError(e)}')));
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share),
                  title: const Text('Поделиться'),
                  onTap: () async {
                    Navigator.pop(c);
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      final path = await AppwriteService.downloadFileToTemp(m.mediaId!, filename: '${m.mediaId}');
                      await AppwriteService.shareFile(path, text: m.content.isNotEmpty ? m.content : null);
                    } catch (e) {
                      messenger.showSnackBar(SnackBar(content: Text('Ошибка: ${AppwriteService.readableError(e)}')));
                    }
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showReactionPicker(Message m) {
    showModalBottomSheet(
      context: context,
      builder: (c) {
        final emojis = ['👍', '❤️', '😂', '😮', '😢', '🔥'];
        return SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: emojis
                .map(
                  (e) => IconButton(
                    onPressed: () async {
                      Navigator.pop(c);
                      try {
                        await AppwriteService.reactMessage(_chatId!, m.id, e);
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Реакция отправлена')));
                      } catch (err) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: ${AppwriteService.readableError(err)}')));
                      }
                    },
                    icon: Text(e, style: const TextStyle(fontSize: 24)),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  Future<void> _downloadOrPreviewFile(Message m) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      // Получаем информацию о файле, если еще не получали
      if (!_mediaInfo.containsKey(m.mediaId)) {
        final info = await AppwriteService.getFileInfo(m.mediaId!);
        _mediaInfo[m.mediaId!] = info;
      }

      final info = _mediaInfo[m.mediaId]!;
      final mimeType = info['mimeType'] as String;
      final originalName = info['name'] as String;

      final local = await AppwriteService.downloadFileToTemp(
        m.mediaId!,
        filename: originalName,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // закрываем диалог загрузки

      if (mimeType.startsWith('image/')) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MediaViewer(
            localPath: local,
            title: m.content.isNotEmpty ? m.content : originalName,
          ),
        ));
      } else if (mimeType.startsWith('video/')) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MediaPlayer(
            localPath: local,
            networkUrl: AppwriteService.getFileViewUrl(m.mediaId!).toString(),
          ),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Файл сохранён: $local')),
        );
      }
    } catch (e) {
      try { Navigator.of(context).pop(); } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: ${AppwriteService.readableError(e)}')),
        );
      }
    }
  }

  Widget _buildMessageBubble(Message m) {
    final isMe = m.senderId == _meId;
  final bg = isMe ? Color(SettingsService.themeNotifier.value.primaryColorValue) : Theme.of(context).colorScheme.surfaceContainerHighest;
    final Color? textColor = isMe ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color;
    final radius = BorderRadius.circular(UITokens.corner);

    // Загружаем информацию о файле, если еще не загружена
    if (m.mediaId != null && !_mediaInfo.containsKey(m.mediaId)) {
      AppwriteService.getFileInfo(m.mediaId!).then((info) {
        if (mounted) setState(() => _mediaInfo[m.mediaId!] = info);
      }).catchError((_) {});
    }

    return GestureDetector(
      onLongPress: () => _onLongPressMessage(m),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) UserAvatar(radius: 18, avatarUrl: null, initials: null),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: radius,
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (m.replyTo != null && m.replyTo!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(6),
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Ответ: ${m.replyTo}',
                            style: TextStyle(fontSize: 12, color: textColor),
                          ),
                        ),
                      if (m.mediaId != null)
                        if (m.type == 'file')
                          GestureDetector(
                            onTap: () => _downloadOrPreviewFile(m),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              width: 220,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.insert_drive_file),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      m.content.isNotEmpty ? m.content : 'Файл',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_mediaInfo.containsKey(m.mediaId))
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width * 0.7,
                                    maxHeight: 300,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: MediaPreview(
                                      mediaId: m.mediaId!,
                                      mimeType: m.type == 'video' ? 'video/mp4' : 'image/jpeg',
                                      maxHeight: 300,
                                      autoDownload: true,
                                    ),
                                  ),
                                )
                              else
                                GestureDetector(
                                  onTap: () async {
                                    final navigator = Navigator.of(context);
                                    try {
                                      showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
                                      final local = await AppwriteService.downloadFileToTemp(m.mediaId!, filename: '${m.mediaId}');
                                      navigator.pop();
                                      if (!mounted) return;
                                      navigator.push(MaterialPageRoute(builder: (_) => MediaViewer(localPath: local, title: m.content.isNotEmpty ? m.content : null)));
                                    } catch (e) {
                                      try { navigator.pop(); } catch (_) {}
                                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось открыть медиа: ${AppwriteService.readableError(e)}')));
                                    }
                                  },
                                  child: Container(
                                    width: 220,
                                    height: 220,
                                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    child: FadeInImage.assetNetwork(
                                      placeholder: 'assets/icon/app_icon.png',
                                      image: AppwriteService.getFileViewUrl(m.mediaId!).toString(),
                                      width: 220 * Responsive.scaleWidth(context),
                                      height: 220 * Responsive.scaleWidth(context),
                                      fit: BoxFit.cover,
                                      imageErrorBuilder: (c, e, st) => Center(child: Icon(Icons.broken_image, size: 40, color: Theme.of(context).iconTheme.color)),
                                      fadeInDuration: const Duration(milliseconds: 200),
                                      fadeOutDuration: const Duration(milliseconds: 100),
                                    ),
                                  ),
                                ),
                              if (m.content.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  child: Text(m.content, style: TextStyle(color: textColor)),
                                ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_formatTime(m.time), style: TextStyle(fontSize: 11, color: textColor?.withAlpha((0.8 * 255).round()) ?? Colors.black54)),
                                  if (m.readBy.isNotEmpty) const SizedBox(width: 6),
                                  if (m.readBy.isNotEmpty) const Icon(Icons.done_all, size: 14),
                                  if (m.id.startsWith('local_')) const SizedBox(width: 6),
                                  if (m.id.startsWith('local_')) const Icon(Icons.access_time, size: 12),
                                ],
                              ),
                            ],
                          ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    try {
      final h = t.hour.toString().padLeft(2, '0');
      final m = t.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '';
    }
  }

  Widget _buildShimmer() {
    return ListView.builder(
      reverse: true,
      itemCount: 8,
      itemBuilder: (c, i) {
        final alignRight = i % 2 == 0;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Row(
            mainAxisAlignment: alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Shimmer.fromColors(
                  baseColor: Colors.grey[300]!,
                  highlightColor: Colors.grey[100]!,
                  child: Container(height: 18 + (i % 3) * 6, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Color(SettingsService.themeNotifier.value.primaryColorValue);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0.5,
        title: Row(
          children: [
            UserAvatar(avatarUrl: _peerAvatarUrl ?? widget.avatarUrl, radius: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_peerDisplayName ?? widget.title ?? 'Чат', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(_formatUserStatusFromPrefs(_peerPrefs).isEmpty ? '' : _formatUserStatusFromPrefs(_peerPrefs), style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
                ],
              ),
            ),
          ],
        ),
        iconTheme: IconThemeData(color: primary),
        actions: [
          // manual sync button
          _syncing
              ? Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(
                  onPressed: () async {
                    final scaffold = ScaffoldMessenger.of(context);
                    setState(() => _syncing = true);
                    try {
                      await _syncFromServer();
                      if (mounted) scaffold.showSnackBar(const SnackBar(content: Text('Чат обновлён')));
                    } catch (_) {}
                    if (mounted) setState(() => _syncing = false);
                  },
                  icon: const Icon(Icons.refresh),
                ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'profile') {
                if (_peerPrefs != null || widget.peerId != null) {
                  final uid = widget.peerId ?? _peerPrefs?['userId']?.toString();
                  if (uid != null && uid.isNotEmpty) Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: uid, initialName: _peerDisplayName, initialAvatar: _peerAvatarUrl)));
                }
              } else if (v == 'clear') {
                if (_chatId != null) {
                  await _localStore.clearChat(_chatId!);
                  if (mounted) setState(() => _messages = []);
                }
              } else if (v == 'delete') {
                if (_chatId != null) {
                  final scaffold = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);
                  try {
                    await AppwriteService.deleteChat(_chatId!, false);
                    if (mounted) {
                      scaffold.showSnackBar(const SnackBar(content: Text('Чат скрыт')));
                      navigator.pop();
                    }
                  } catch (e) {
                    if (mounted) scaffold.showSnackBar(SnackBar(content: Text('Не удалось удалить чат: ${AppwriteService.readableError(e)}')));
                  }
                }
              }
            },
            itemBuilder: (c) => [
              const PopupMenuItem(value: 'profile', child: Text('Просмотр профиля')),
              const PopupMenuItem(value: 'clear', child: Text('Очистить переписку')),
              const PopupMenuItem(value: 'delete', child: Text('Удалить чат')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_uploading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.0),
              child: LinearProgressIndicator(value: (_uploadProgress > 0 && _uploadProgress <= 1) ? _uploadProgress : null),
            ),
          Expanded(
            child: (() {
              if (_loading) return _buildShimmer();
              if (_messages.isEmpty) return Center(child: Text('Нет сообщений', style: Theme.of(context).textTheme.bodyLarge));
              return RefreshIndicator(
                onRefresh: _loadMessages,
                child: ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  itemCount: _messages.length,
                  itemBuilder: (c, i) => _buildMessageBubble(_messages[i]),
                  cacheExtent: 800, // Предзагрузка элементов для плавности
                  padding: EdgeInsets.symmetric(
                    vertical: 8 * Responsive.scaleHeight(context),
                    horizontal: 12 * Responsive.scaleWidth(context),
                  ),
                ),
              );
            })(),
          ),
          if (_replyToMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Expanded(child: Text('Ответ: ${_replyToMessage!.content}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _replyToMessage = null;
                        _replyToMessageId = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          if (_pendingImage != null)
            Container(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Image.file(File(_pendingImage!.path), width: 64, height: 64, fit: BoxFit.cover),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_pendingImage!.name)),
                  IconButton(onPressed: () => setState(() => _pendingImage = null), icon: const Icon(Icons.close)),
                ],
              ),
            ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(onPressed: _pickImage, icon: Icon(Icons.attach_file, color: primary)),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Сообщение',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(UITokens.corner), borderSide: BorderSide.none),
                        filled: true,
                        fillColor: Theme.of(context).cardColor,
                      ),
                    ),
                  ),
                  IconButton(onPressed: (_chatId == null || _loading || _uploading) ? null : () => _sendMessage(), icon: Icon(Icons.send, color: primary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
