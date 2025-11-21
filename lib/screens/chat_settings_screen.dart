import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:two_space_app/services/matrix_service.dart';
import 'package:two_space_app/services/chat_matrix_service.dart';

class ChatSettingsScreen extends StatefulWidget {
  final String roomId;
  final String initialName;
  const ChatSettingsScreen({super.key, required this.roomId, required this.initialName});

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  final _nameController = TextEditingController();
  bool _saving = false;
  bool _isPublic = false;
  int _selectedIndex = 0;
  List<Map<String, dynamic>> _members = [];
  bool _loadingMembers = false;
  final _svc = ChatMatrixService();

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialName;
  }

  Future<void> _pickAndUploadAvatar() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    setState(() => _saving = true);
    try {
      await MatrixService.setRoomAvatarFromFile(widget.roomId, path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Аватар комнаты обновлен')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка при загрузке аватара: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      final name = _nameController.text.trim();
      if (name.isNotEmpty) await MatrixService.setRoomName(widget.roomId, name);
      // set join rule
      await ChatMatrixService().setJoinRule(widget.roomId, _isPublic ? 'public' : 'invite');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Настройки комнаты сохранены')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка при сохранении: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections = [
      {'key': 'invite', 'title': 'Пригласить', 'icon': Icons.person_add},
      {'key': 'members', 'title': 'Участники', 'icon': Icons.group},
      {'key': 'threads', 'title': 'Ветки', 'icon': Icons.alt_route},
      {'key': 'pinned', 'title': 'Закрепленные', 'icon': Icons.push_pin},
      {'key': 'files', 'title': 'Файлы', 'icon': Icons.folder},
      {'key': 'media', 'title': 'Медиа', 'icon': Icons.image},
      {'key': 'extensions', 'title': 'Расширения', 'icon': Icons.extension},
      {'key': 'copylink', 'title': 'Копировать ссылку', 'icon': Icons.link},
      {'key': 'polls', 'title': 'Опросы', 'icon': Icons.poll},
      {'key': 'export', 'title': 'Экспорт чата', 'icon': Icons.download},
      {'key': 'settings', 'title': 'Настройки', 'icon': Icons.settings},
      {'key': 'report', 'title': 'Пожаловаться', 'icon': Icons.flag, 'danger': true},
      {'key': 'leave', 'title': 'Покинуть комнату', 'icon': Icons.exit_to_app, 'danger': true},
    ];

    return Scaffold(
      appBar: AppBar(title: Text('Комната — ${widget.initialName}')),
      body: Row(children: [
        Container(width: 260, color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.06), child: Column(children: [
          const SizedBox(height: 12),
          ...List.generate(sections.length, (i) {
            final s = sections[i];
            return ListTile(
              leading: Icon(s['icon'] as IconData, color: s['danger'] == true ? Colors.red : null),
              title: Text(s['title'] as String, style: s['danger'] == true ? const TextStyle(color: Colors.red) : null),
              trailing: (s['key'] == 'pinned') ? const Chip(label: Text('0')) : null,
              selected: _selectedIndex == i,
              onTap: () async {
                setState(() => _selectedIndex = i);
                if (s['key'] == 'members') await _loadMembers();
              },
            );
          }),
        ])),
        Expanded(child: Padding(padding: const EdgeInsets.all(16.0), child: _buildSectionContent(sections[_selectedIndex]['key'] as String))),
      ]),
    );
  }

  Widget _buildSectionContent(String key) {
    switch (key) {
      case 'members':
        return _buildMembers();
      case 'settings':
        return _buildSettings();
      default:
        return Center(child: Text('Заглушка — $key'));
    }
  }

  Widget _buildMembers() {
    if (_loadingMembers) return const Center(child: CircularProgressIndicator());
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Участники', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      Expanded(child: ListView.separated(itemBuilder: (c, i) {
        final m = _members[i];
        return ListTile(leading: CircleAvatar(backgroundImage: m['avatarUrl'] != null ? NetworkImage(m['avatarUrl']!) : null, child: m['avatarUrl'] == null ? Text((m['displayName'] ?? m['userId'] ?? '?')![0]) : null), title: Text(m['displayName'] ?? m['userId'] ?? ''), subtitle: Text(m['userId'] ?? ''));
      }, separatorBuilder: (_, __) => const Divider(), itemCount: _members.length))
    ]);
  }

  Widget _buildSettings() {
    // reuse old settings UI
    return SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Общие', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Название комнаты')),
      const SizedBox(height: 12),
      Row(children: [ElevatedButton.icon(onPressed: _saving ? null : _pickAndUploadAvatar, icon: const Icon(Icons.image), label: const Text('Загрузить аватар'))]),
      const SizedBox(height: 16),
      SwitchListTile(
        title: const Text('Публичная комната'),
        subtitle: const Text('Опубликовать комнату в каталоге и разрешить всем присоединяться'),
        value: _isPublic,
        onChanged: (v) => setState(() => _isPublic = v),
      ),
      const SizedBox(height: 8),
      Row(children: [TextButton(onPressed: _saving ? null : _saveSettings, child: _saving ? const CircularProgressIndicator() : const Text('Сохранить'))])
    ]));
  }

  Future<void> _loadMembers() async {
    setState(() { _loadingMembers = true; _members = []; });
    try {
      final list = await _svc.getRoomMembers(widget.roomId);
      if (!mounted) return;
      setState(() { _members = list; });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки участников: $e')));
    } finally { if (mounted) setState(() => _loadingMembers = false); }
  }
}
