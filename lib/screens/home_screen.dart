import 'package:flutter/material.dart';
import 'package:two_space_app/services/chat_matrix_service.dart';
import 'package:two_space_app/models/chat.dart';
import 'package:two_space_app/screens/chat_screen.dart';
import 'package:two_space_app/screens/chat_settings_screen.dart';
import 'package:two_space_app/widgets/app_logo.dart';

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

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    setState(() => _loading = true);
    try {
      // Placeholder: real Matrix room discovery should be implemented here.
      // For now we display example rooms so the responsive layout and
      // settings UI can be exercised on desktop.
    } catch (_) {}
    // For now, show placeholder rooms to let UI layout and settings be used.
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

  Widget _buildLeftColumn(double width) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(children: [
        SizedBox(height: 12),
        const AppLogo(large: false),
        const SizedBox(height: 8),
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
                      selected: selected,
                      title: Text(name),
                      leading: CircleAvatar(child: Text(name.isEmpty ? '?' : name[0].toUpperCase())),
                      onTap: () {
                        setState(() {
                          _selectedRoomId = id;
                          _selectedRoomName = name;
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
    return ChatScreen(chat: chat);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const AppLogo(large: false)),
      body: LayoutBuilder(builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final isThree = maxW >= 1200;
        final isTwo = maxW >= 900 && !isThree;

        if (isThree) {
          return Row(children: [
            SizedBox(width: 320, child: _buildLeftColumn(320)),
            const VerticalDivider(width: 1),
            Expanded(child: _buildCenter()),
            const VerticalDivider(width: 1),
            SizedBox(width: 380, child: ChatSettingsScreen(roomId: _selectedRoomId ?? '', initialName: _selectedRoomName)),
          ]);
        }

        if (isTwo) {
          return Row(children: [
            SizedBox(width: 360, child: _buildLeftColumn(360)),
            const VerticalDivider(width: 1),
            Expanded(child: _buildCenter()),
          ]);
        }

        // single column
        return _buildLeftColumn(maxW);
      }),
    );
  }
}