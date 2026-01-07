import 'package:flutter/material.dart';
import 'package:two_space_app/services/chat_matrix_service.dart';
import 'package:two_space_app/services/auth_service.dart';
import 'package:two_space_app/models/chat.dart';
import 'package:two_space_app/screens/chat_screen.dart';
import 'package:two_space_app/screens/group_settings_screen.dart';
import 'package:two_space_app/widgets/user_avatar.dart';
import '../utils/responsive.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ChatMatrixService _chat = ChatMatrixService();
  List<Map<String, dynamic>> _rooms = [];
  String? _selectedRoomId;
  String _selectedRoomName = '';
  bool _loading = true;
  bool _rightOpen = true;

  String _searchQuery = '';
  String _searchType = 'all';

  @override
  void initState() {
    super.initState();
    _checkAuthAndLoadRooms();
  }

  Future<void> _checkAuthAndLoadRooms() async {
    try {
      final auth = AuthService();
      final token = await auth.getMatrixTokenForUser();
      if (token == null || token.isEmpty) {
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
        return;
      }
      await _loadRooms();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  Future<void> _loadRooms() async {
    setState(() => _loading = true);
    try {
      final ids = await _chat.getJoinedRooms();
      final out = <Map<String, dynamic>>[];
      for (final id in ids) {
        final meta = await _chat.getRoomNameAndAvatar(id);
        out.add({'roomId': id, 'name': meta['name'] ?? id, 'avatar': meta['avatar']});
      }
      setState(() {
        _rooms = out;
        if (_rooms.isNotEmpty) {
          _selectedRoomId = _rooms.first['roomId'] as String?;
          _selectedRoomName = _rooms.first['name'] as String? ?? '';
        }
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _rooms = [
          {'roomId': '!example1:matrix.org', 'name': 'Общий чат'},
          {'roomId': '!example2:matrix.org', 'name': 'Разработка'},
          {'roomId': '!example3:matrix.org', 'name': 'Тестовый'},
        ];
        if (_rooms.isNotEmpty) {
          _selectedRoomId = _rooms.first['roomId'] as String?;
          _selectedRoomName = _rooms.first['name'] as String? ?? '';
        }
        _loading = false;
      });
    }
  }

  Widget _buildLeftColumn(double width) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(children: [
        const SizedBox(height: 12),
        // Search field (moved here from center). Keep the app title in the AppBar only.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Поиск',
              isDense: true,
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Row(children: [
            PopupMenuButton<String>(
              tooltip: 'Тип поиска',
              icon: const Icon(Icons.filter_list),
              onSelected: (v) => setState(() => _searchType = v),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'all', child: Row(children: [Expanded(child: Text('Все')), if (_searchType == 'all') const Icon(Icons.check, size: 16)])),
                PopupMenuItem(value: 'messages', child: Row(children: [Expanded(child: Text('Сообщения')), if (_searchType == 'messages') const Icon(Icons.check, size: 16)])),
                PopupMenuItem(value: 'media', child: Row(children: [Expanded(child: Text('Медиа')), if (_searchType == 'media') const Icon(Icons.check, size: 16)])),
                PopupMenuItem(value: 'users', child: Row(children: [Expanded(child: Text('Пользователи')), if (_searchType == 'users') const Icon(Icons.check, size: 16)])),
              ],
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rooms.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 64 * Responsive.scaleFor(context),
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          ),
                          SizedBox(height: 16 * Responsive.scaleHeight(context)),
                          Text(
                            'Нет чатов',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontSize: 20 * Responsive.scaleFor(context),
                            ),
                          ),
                          SizedBox(height: 8 * Responsive.scaleHeight(context)),
                          Text(
                            'Присоединитесь к комнате или создайте новую',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 14 * Responsive.scaleFor(context),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.all(8 * Responsive.scaleWidth(context)),
                      itemCount: _rooms.length,
                      separatorBuilder: (_, __) => SizedBox(height: 6 * Responsive.scaleHeight(context)),
                      itemBuilder: (context, index) {
                        final r = _rooms[index];
                        final id = r['roomId'] as String? ?? '';
                        final name = r['name'] as String? ?? id;
                        final selected = _selectedRoomId == id;
                        return ListTile(
                          key: ValueKey(id),
                          selected: selected,
                          selectedTileColor: Theme.of(context).colorScheme.surface.withOpacity(0.06),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12 * Responsive.scaleWidth(context)),
                          ),
                          title: Text(
                            name,
                            style: TextStyle(fontSize: 16 * Responsive.scaleFor(context)),
                          ),
                          leading: r['avatar'] != null
                              ? UserAvatar(avatarUrl: r['avatar'] as String?, radius: 20 * Responsive.scaleFor(context))
                              : CircleAvatar(
                                radius: 20 * Responsive.scaleFor(context),
                                child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
                              ),
                          onTap: () {
                            setState(() {
                              _selectedRoomId = id;
                              _selectedRoomName = name;
                              // open center and right when selecting
                              _rightOpen = true;
                            });
                          },
                        );
                      },
                    ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = Responsive.scaleFor(context);
        final isWide = constraints.maxWidth > 800;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Home',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontSize: 24 * scale,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          body: Row(
            children: [
              if (isWide)
                Expanded(
                  flex: 2,
                  child: Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: _buildLeftColumn(300.0),
                  ),
                ),
              Expanded(
                flex: 5,
                child: _buildMainContent(scale),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMainContent(double scale) {
    if (_selectedRoomId == null) {
      return const Center(child: Text('Выберите комнату'));
    }
  final chat = Chat(id: _selectedRoomId!, name: _selectedRoomName, members: []);
  return Column(children: [
        // header with title
      Container(
        color: Theme.of(context).colorScheme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _rightOpen = !_rightOpen);
              },
              child: Row(children: [
                Text(_selectedRoomName, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(width: 8),
                const Icon(Icons.open_in_new, size: 18),
              ]),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Информация о группе',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupSettingsScreen(roomId: _selectedRoomId!),
                ),
              );
            },
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(child: ChatScreen(key: ValueKey(chat.id), chat: chat, searchQuery: _searchQuery, searchType: _searchType)),
      Container(
        color: Theme.of(context).colorScheme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _rightOpen = !_rightOpen);
              },
              child: Row(children: [
                Text(_selectedRoomName, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(width: 8),
                const Icon(Icons.open_in_new, size: 18),
              ]),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Информация о группе',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupSettingsScreen(roomId: _selectedRoomId!),
                ),
              );
            },
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(child: ChatScreen(key: ValueKey(chat.id), chat: chat, searchQuery: _searchQuery, searchType: _searchType)),
    ]);
  }
}