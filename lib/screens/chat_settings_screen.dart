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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки комнаты'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveSettings,
            child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator.adaptive(strokeWidth: 2)) : const Text('Сохранить', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          if (_saving) const LinearProgressIndicator(minHeight: 3),
        ]),
      ),
    );
  }
}
