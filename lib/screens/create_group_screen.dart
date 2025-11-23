import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/group_matrix_service.dart';
import '../models/group.dart';
import '../models/chat.dart';
import 'chat_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({Key? key}) : super(key: key);

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  File? _selectedImage;
  GroupVisibility _visibility = GroupVisibility.private;
  bool _showMessageHistory = false;
  bool _isLoading = false;

  late GroupMatrixService _groupService;

  @override
  void initState() {
    super.initState();
    _groupService = GroupMatrixService();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выбора изображения: $e')),
        );
      }
    }
  }

  Future<void> _createGroup() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пожалуйста, введите название комнаты')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final group = await _groupService.createGroupRoom(
        name: _nameController.text,
        description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
        visibility: _visibility,
        showMessageHistory: _showMessageHistory,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Комната успешно создана!')),
        );
        // Создаем Chat объект из GroupRoom
        final chatObj = Chat(
          id: group.roomId,
          name: group.name,
          avatarUrl: null,
          members: group.members.map((m) => m.userId).toList(),
          lastMessage: '',
          roomType: 'group',
          lastMessageTime: DateTime.now(),
        );
        // Навигация в созданную комнату
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ChatScreen(chat: chatObj),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth > 600;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Создать комнату'),
        centerTitle: !isWideScreen,
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextButton.icon(
              onPressed: _isLoading ? null : _createGroup,
              icon: _isLoading ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary))) : const Icon(Icons.check),
              label: const Text('Создать'),
              style: TextButton.styleFrom(
                backgroundColor: _isLoading ? null : theme.colorScheme.primary.withOpacity(0.1),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isWideScreen ? screenWidth * 0.2 : 16,
                vertical: 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar selector
                  Center(
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[800] : Colors.grey[200],
                          borderRadius: BorderRadius.circular(60),
                          border: Border.all(
                            color: theme.colorScheme.primary.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: _selectedImage != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(60),
                                child: Image.file(
                                  _selectedImage!,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Icon(
                                Icons.add_a_photo,
                                size: 40,
                                color: theme.colorScheme.primary.withOpacity(0.6),
                              ),
                      ),
                    ),
                  ),
                  SizedBox(height: 24),

                  // Group name field
                  Text(
                    'Название комнаты',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: 'Например, название вашего проекта',
                      filled: true,
                      fillColor: isDark ? Colors.grey[900] : Colors.grey[50],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outline.withOpacity(0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outline.withOpacity(0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                  SizedBox(height: 24),

                  // Description field
                  Text(
                    'Тема (необязательно)',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'О чем эта комната?',
                      filled: true,
                      fillColor: isDark ? Colors.grey[900] : Colors.grey[50],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outline.withOpacity(0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outline.withOpacity(0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                  SizedBox(height: 24),

                  // Visibility section
                  Text(
                    'Видимость комнаты',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 12),
                  _buildVisibilityOption(
                    title: 'Частная комната',
                    subtitle: 'Доступ имеют только приглашенные пользователи. Сквозное шифрование.',
                    value: GroupVisibility.private,
                    icon: Icons.lock,
                  ),
                  SizedBox(height: 12),
                  _buildVisibilityOption(
                    title: 'Общедоступная комната',
                    subtitle: 'Любой может найти. Можно изменить в настройках.',
                    value: GroupVisibility.public,
                    icon: Icons.public,
                  ),
                  SizedBox(height: 24),

                  // Message history checkbox
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.outline.withOpacity(0.2),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: CheckboxListTile(
                      value: _showMessageHistory,
                      onChanged: (value) {
                        setState(() => _showMessageHistory = value ?? false);
                      },
                      title: Text(
                        'Показывать историю сообщений',
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        'Новые пользователи смогут видеть предыдущие сообщения',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                  SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildVisibilityOption({
    required String title,
    required String subtitle,
    required GroupVisibility value,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final isSelected = _visibility == value;

    return GestureDetector(
      onTap: () => setState(() => _visibility = value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outline.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? theme.colorScheme.primary.withOpacity(0.08) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outline,
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: isSelected ? theme.colorScheme.primary : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            Radio<GroupVisibility>(
              value: value,
              groupValue: _visibility,
              onChanged: (newValue) {
                if (newValue != null) {
                  setState(() => _visibility = newValue);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
