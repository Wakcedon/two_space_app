import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:two_space_app/services/chat_matrix_service.dart';
import 'package:two_space_app/models/chat.dart';
import 'package:two_space_app/screens/chat_screen.dart';
import 'package:two_space_app/screens/chat_settings_screen.dart';
import 'package:two_space_app/widgets/app_logo.dart';
import 'package:two_space_app/screens/account_settings_screen.dart';
import 'package:two_space_app/widgets/user_avatar.dart';

/// A simplified, responsive HomeScreen that provides:
/// - Two-pane layout on wide screens (chat list + chat)
/// - Three-pane layout on very wide screens (chat list + chat + settings)
/// - Single-column layout on small screens (chat list)
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
  // layout state
  double _leftWidth = 320;
  double _rightWidth = 380;
  bool _rightOpen = true;

  // search state
  String _searchQuery = '';
  String _searchType = 'all';

  @override
  void initState() {
    super.initState();
    _loadRooms();
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
      // on failure, fall back to example placeholders so UI remains functional
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
              fillColor: Theme.of(context).colorScheme.surfaceVariant,
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
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: _rooms.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final r = _rooms[index];
                    final id = r['roomId'] as String? ?? '';
                    final name = r['name'] as String? ?? id;
                    final selected = _selectedRoomId == id;
                    return ListTile(
                      key: ValueKey(id),
                      selected: selected,
                      selectedTileColor: Theme.of(context).colorScheme.surface.withOpacity(0.06),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      title: Text(name),
            leading: r['avatar'] != null
              ? UserAvatar(avatarUrl: r['avatar'] as String?, radius: 20)
              : CircleAvatar(child: Text(name.isEmpty ? '?' : name[0].toUpperCase())),
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

  Widget _buildCenter() {
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
          SizedBox(width: 170, child: Row(children: [
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
            const SizedBox(width: 12),
            Text(''),
          ])),
        ]),
      ),
      const Divider(height: 1),
      Expanded(child: ChatScreen(key: ValueKey(chat.id), chat: chat, searchQuery: _searchQuery, searchType: _searchType)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const AppLogo(large: false), actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12.0),
          child: GestureDetector(
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountSettingsScreen()));
              // refresh rooms in case user changed accounts
              await _loadRooms();
            },
            child: CircleAvatar(child: Text((_selectedRoomName.isNotEmpty ? _selectedRoomName[0] : 'U'))),
          ),
        ),
      ]),
      body: LayoutBuilder(builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final isThree = maxW >= 1200;
        final isTwo = maxW >= 900 && !isThree;

  // adjust left/right widths to sensible bounds (ensure clamp upper >= lower)
  final leftMin = 220.0;
  final rightMin = 240.0;
  // compute upper bounds based on available width
  final leftMax = math.max(leftMin, maxW - ( (_rightOpen && isThree) ? (_rightWidth + 300.0) : 300.0));
  final rightMax = math.max(rightMin, maxW - (_leftWidth + 200.0));
  _leftWidth = _leftWidth.clamp(leftMin, leftMax);
  _rightWidth = _rightWidth.clamp(rightMin, rightMax);

        if (isThree && _rightOpen) {
          return Row(children: [
            SizedBox(width: _leftWidth, child: _buildLeftColumn(_leftWidth)),
            // draggable divider
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanUpdate: (d) => setState(() => _leftWidth = (_leftWidth + d.delta.dx).clamp(220.0, maxW - 400.0)),
              child: const VerticalDivider(width: 12, thickness: 1),
            ),
            Expanded(child: _buildCenter()),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanUpdate: (d) => setState(() => _rightWidth = (_rightWidth - d.delta.dx).clamp(240.0, maxW - 400.0)),
              child: const VerticalDivider(width: 12, thickness: 1),
            ),
            SizedBox(width: _rightWidth, child: ChatSettingsScreen(roomId: _selectedRoomId ?? '', initialName: _selectedRoomName)),
          ]);
        }

        if (isThree && !_rightOpen) {
          // right closed: two-pane layout with left + center
          return Row(children: [
            SizedBox(width: _leftWidth, child: _buildLeftColumn(_leftWidth)),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanUpdate: (d) => setState(() => _leftWidth = (_leftWidth + d.delta.dx).clamp(220.0, maxW - 300.0)),
              child: const VerticalDivider(width: 12, thickness: 1),
            ),
            Expanded(child: _buildCenter()),
          ]);
        }

        if (isTwo) {
          return Row(children: [
            SizedBox(width: _leftWidth, child: _buildLeftColumn(_leftWidth)),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanUpdate: (d) => setState(() => _leftWidth = (_leftWidth + d.delta.dx).clamp(220.0, maxW - 300.0)),
              child: const VerticalDivider(width: 12, thickness: 1),
            ),
            Expanded(child: _buildCenter()),
          ]);
        }

        // single column
        return _buildLeftColumn(maxW);
      }),
      // add user icon in the app bar actions
      floatingActionButton: null,
    );
  }
}