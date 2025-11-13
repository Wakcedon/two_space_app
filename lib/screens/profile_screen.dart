import 'package:flutter/material.dart';
import 'package:two_space_app/services/appwrite_service.dart';
import 'package:two_space_app/services/chat_service.dart';
import 'package:two_space_app/services/settings_service.dart';
import 'package:two_space_app/services/navigation_service.dart';
import 'package:two_space_app/config/ui_tokens.dart';
import 'package:two_space_app/widgets/user_avatar.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  final String? initialName;
  final String? initialAvatar;

  const ProfileScreen({super.key, required this.userId, this.initialName, this.initialAvatar});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _user;
  bool _loading = true;
  bool _actionLoading = false;
  bool _isMe = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final u = await AppwriteService.getUserById(widget.userId);
      final me = await AppwriteService.getCurrentUserId();
      if (mounted) setState(() {
        _user = u.isNotEmpty ? Map<String, dynamic>.from(u) : null;
        _isMe = (me != null && me == widget.userId);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _user = null; });
    }
  }

  String _displayName() {
    try {
      if (_user == null) return widget.initialName ?? widget.userId;
      final prefs = (_user!['prefs'] is Map) ? Map<String, dynamic>.from(_user!['prefs']) : <String, dynamic>{};
      final name = (_user!['name'] as String?)?.trim();
      if (name != null && name.isNotEmpty) return name;
      final nick = (prefs['nickname'] as String?)?.trim();
      if (nick != null && nick.isNotEmpty) return nick;
      final email = (_user!['email'] as String?) ?? '';
      if (email.isNotEmpty) return email.split('@').first;
    } catch (_) {}
    return widget.initialName ?? widget.userId;
  }

  String? _avatarUrl() {
    try {
      if (_user != null) {
        final prefs = (_user!['prefs'] is Map) ? Map<String, dynamic>.from(_user!['prefs']) : <String, dynamic>{};
        return (prefs['avatarUrl'] as String?) ?? (_user!['avatar'] as String?);
      }
    } catch (_) {}
    return widget.initialAvatar;
  }

  @override
  Widget build(BuildContext context) {
    final name = _displayName();
    final avatar = _avatarUrl();
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Профиль'),
        centerTitle: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(UITokens.space),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: UserAvatar(key: ValueKey(avatar ?? 'noavatar_${widget.userId}'), avatarUrl: avatar, initials: (name.isNotEmpty ? name[0] : '?'), fullName: name, radius: 56),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(child: Text(name, style: Theme.of(context).textTheme.headlineSmall)),
                  const SizedBox(height: 6),
                  if (_user != null) ...[
                    Center(child: Text('@${_user!['prefs']?['nickname'] ?? _user!['name'] ?? ''}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface.withAlpha((0.7 * 255).round())))),
                    const SizedBox(height: 16),
                  ],
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    ElevatedButton.icon(
                      onPressed: _actionLoading ? null : () async {
                        setState(() => _actionLoading = true);
                        try {
                          final cs = ChatService();
                          final m = await cs.getOrCreateDirectChat(widget.userId);
                          final chat = Chat.fromMap(m);
                          if (!mounted) return;
                          // Return created/selected chat to caller so HomeScreen can react (select on two-pane)
                          appNavigatorKey.currentState?.pop(chat);
                        } catch (e) {
                          if (!mounted) return;
                          final navCtx = appNavigatorKey.currentContext;
                          if (navCtx != null) ScaffoldMessenger.of(navCtx).showSnackBar(SnackBar(content: Text('Не удалось создать чат: ${AppwriteService.readableError(e)}')));
                        } finally {
                          if (mounted) setState(() => _actionLoading = false);
                        }
                      },
                      icon: _actionLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.chat_bubble_outline),
                      label: const Text('Написать'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.call_outlined),
                      label: const Text('Позвонить'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.more_vert),
                      label: const Text('Ещё'),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  Card(
                    elevation: UITokens.cardElevation,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UITokens.corner)),
                    child: Padding(
                      padding: const EdgeInsets.all(UITokens.space),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _buildInfoRow('О себе', (_user != null) ? (_user!['prefs']?['about'] ?? _user!['bio'] ?? '') : ''),
                        const Divider(),
                        // Email: show depending on user's preferences or local settings if viewing own profile
                        if (_user != null)
                          Builder(builder: (c) {
                            final prefs = (_user!['prefs'] is Map) ? Map<String, dynamic>.from(_user!['prefs']) : <String, dynamic>{};
                            final serverShowEmail = prefs['showEmail'] == true;
                            final email = (_user!['email'] as String?) ?? '';
                            final shouldShowEmail = (_isMe ? SettingsService.showEmailNotifier.value : serverShowEmail);
                            if (email.isNotEmpty && shouldShowEmail) return Column(children: [
                              _buildInfoRow('Email', email),
                              const Divider(),
                            ]);
                            return const SizedBox.shrink();
                          }),

                        // Phone: similar visibility rules
                        if (_user != null)
                          Builder(builder: (c) {
                            final prefs = (_user!['prefs'] is Map) ? Map<String, dynamic>.from(_user!['prefs']) : <String, dynamic>{};
                            final serverShowPhone = prefs['showPhone'] == true;
                            final phone = (_user!['phone'] as String?) ?? '';
                            final shouldShowPhone = (_isMe ? SettingsService.showPhoneNotifier.value : serverShowPhone);
                            if (phone.isNotEmpty && shouldShowPhone) return Column(children: [
                              _buildInfoRow('Телефон', phone),
                              const Divider(),
                            ]);
                            return const SizedBox.shrink();
                          }),

                        _buildInfoRow('Никнейм', (_user != null) ? (_user!['prefs']?['nickname'] ?? '') : ''),
                        const Divider(),
                        _buildInfoRow('Место', (_user != null) ? (_user!['location'] ?? '') : ''),
                        const Divider(),
                        _buildInfoRow('День рождения', (_user != null) ? (_user!['birthday'] ?? '') : ''),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoRow(String title, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value?.isNotEmpty == true ? value! : '-', style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 4),
  Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withAlpha((0.6 * 255).round()))),
      ]),
    );
  }
}
