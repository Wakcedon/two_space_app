import 'package:flutter/material.dart';
import '../models/group.dart';
import '../services/group_matrix_service.dart';

class GroupSettingsScreen extends StatefulWidget {
  final String roomId;

  const GroupSettingsScreen({
    Key? key,
    required this.roomId,
  }) : super(key: key);

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  late GroupMatrixService _groupService;
  int _selectedTabIndex = 0;
  bool _isLoading = false;
  GroupRoom? _currentGroup;

  @override
  void initState() {
    super.initState();
    _groupService = GroupMatrixService();
    _loadGroupData();
  }

  Future<void> _loadGroupData() async {
    setState(() => _isLoading = true);
    try {
      final group = await _groupService.getGroupRoom(widget.roomId);
      if (mounted) {
        setState(() => _currentGroup = group);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _canManageMembers =>
      _currentGroup?.currentUserRole == GroupRole.owner ||
      _currentGroup?.currentUserRole == GroupRole.admin;

  bool get _canDeleteGroup => _currentGroup?.currentUserRole == GroupRole.owner;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth > 800;
        return Scaffold(
          appBar: AppBar(
            title: Text(_currentGroup?.name ?? 'Информация о группе'),
            centerTitle: !isWideScreen,
            elevation: 2,
          ),
          body: _isLoading || _currentGroup == null
              ? const Center(child: CircularProgressIndicator())
              : Row(
                  children: [
                    if (isWideScreen) _buildSidebar(),
                    Expanded(child: _buildSettingsContent()),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildSidebar() {
    final theme = Theme.of(context);
    return Container(
      width: 250,
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          // Tabs с лучшей поддержкой темы
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outline.withOpacity(0.2),
                  ),
                ),
              ),
              child: Row(
                children: [
                  _buildTab(0, 'Информация', Icons.info),
                  _buildTab(1, 'Участники', Icons.people),
                  _buildTab(2, 'Роли', Icons.admin_panel_settings),
                  if (_canManageMembers) _buildTab(3, 'Запреты', Icons.block),
                  if (_canDeleteGroup) _buildTab(4, 'Удалить', Icons.delete),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          // Content
          Expanded(
            child: IndexedStack(
              index: _selectedTabIndex,
              children: [
                _buildInfoTab(),
                _buildMembersTab(),
                _buildRolesTab(),
                if (_canManageMembers) _buildBanListTab(),
                if (_canDeleteGroup) _buildDeleteTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsContent() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tabs с лучшей поддержкой темы (встраиваемые в контент)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTab(0, 'Информация', Icons.info),
                _buildTab(1, 'Участники', Icons.people),
                _buildTab(2, 'Роли', Icons.admin_panel_settings),
                if (_canManageMembers) _buildTab(3, 'Запреты', Icons.block),
                if (_canDeleteGroup) _buildTab(4, 'Удалить', Icons.delete),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Content
          Expanded(
            child: IndexedStack(
              index: _selectedTabIndex,
              children: [
                _buildInfoTab(),
                _buildMembersTab(),
                _buildRolesTab(),
                if (_canManageMembers) _buildBanListTab(),
                if (_canDeleteGroup) _buildDeleteTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(int index, String label, IconData icon) {
    final theme = Theme.of(context);
    final isSelected = _selectedTabIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outline,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? theme.colorScheme.primary : null,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTab() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Название',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.outline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _currentGroup?.name ?? 'Нет названия',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                Text(
                  'Описание',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.outline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _currentGroup?.description ?? 'Нет описания',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Text(
                  'Видимость',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.outline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Chip(
                  label: Text(
                    _currentGroup?.visibility == GroupVisibility.public ? 'Публичная' : 'Приватная',
                  ),
                  backgroundColor: _currentGroup?.visibility == GroupVisibility.public
                      ? theme.colorScheme.primary.withOpacity(0.08)
                      : theme.colorScheme.tertiary.withOpacity(0.2),
                  avatar: Icon(
                    _currentGroup?.visibility == GroupVisibility.public ? Icons.public : Icons.lock,
                    size: 18,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Участников: ${_currentGroup?.memberCount ?? 0}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                if (_canManageMembers) ...[
                  const SizedBox(height: 24),
                  Text(
                    'История сообщений',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.outline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Показывать историю'),
                    subtitle: const Text('Новые участники смогут видеть старые сообщения'),
                    value: _currentGroup?.showMessageHistory ?? false,
                    onChanged: (value) async {
                      try {
                        await _groupService.setShowMessageHistory(widget.roomId, value);
                        await _loadGroupData();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Настройка сохранена')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Ошибка: $e')),
                          );
                        }
                      }
                    },
                  ),
                ],
                if (_currentGroup?.backgroundColor != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Цвет фона',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.outline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 100,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _parseColor(_currentGroup?.backgroundColor),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.outline.withOpacity(0.3),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMembersTab() {
    final theme = Theme.of(context);
    final members = _currentGroup?.members ?? [];
    
    if (members.isEmpty) {
      return Center(
        child: Text(
          'Нет участников',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: members.length,
      itemBuilder: (context, index) {
        final member = members[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primary.withOpacity(0.08),
              backgroundImage: member.avatarUrl != null
                  ? NetworkImage(member.avatarUrl!)
                  : null,
              child: member.avatarUrl == null
                  ? Text(member.displayName.isNotEmpty ? member.displayName[0] : '?')
                  : null,
            ),
            title: Text(
              member.displayName,
              style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
            ),
            subtitle: Chip(
              label: Text(
                member.role.toString().split('.').last.toUpperCase(),
                style: const TextStyle(fontSize: 10),
              ),
              backgroundColor: _getRoleColor(member.role, theme).withOpacity(0.2),
              side: BorderSide(
                color: _getRoleColor(member.role, theme).withOpacity(0.5),
              ),
            ),
            trailing: _canManageMembers
                ? PopupMenuButton(
                    icon: Icon(Icons.more_vert, color: theme.colorScheme.outline),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        child: const Row(
                          children: [Icon(Icons.admin_panel_settings, size: 18), SizedBox(width: 8), Text('Роль')],
                        ),
                        onTap: () => _showRoleDialog(member),
                      ),
                      PopupMenuItem(
                        child: const Row(
                          children: [Icon(Icons.lock, size: 18), SizedBox(width: 8), Text('Заморозить')],
                        ),
                        onTap: () => _showFreezeDialog(member),
                      ),
                      PopupMenuItem(
                        child: const Row(
                          children: [Icon(Icons.block, size: 18), SizedBox(width: 8), Text('Забанить')],
                        ),
                        onTap: () => _banUser(member),
                      ),
                      PopupMenuItem(
                        child: const Row(
                          children: [Icon(Icons.exit_to_app, size: 18), SizedBox(width: 8), Text('Исключить')],
                        ),
                        onTap: () => _kickUser(member),
                      ),
                    ],
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildRolesTab() {
    final theme = Theme.of(context);
    final members = _currentGroup?.members ?? [];
    final owners = members.where((m) => m.role == GroupRole.owner).toList();
    final admins = members.where((m) => m.role == GroupRole.admin).toList();
    final regular = members.where((m) => m.role == GroupRole.member).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRoleSection('👑 Владельцы', owners, _getRoleColor(GroupRole.owner, theme)),
          const SizedBox(height: 16),
          _buildRoleSection('⚡ Администраторы', admins, _getRoleColor(GroupRole.admin, theme)),
          const SizedBox(height: 16),
          _buildRoleSection('👤 Участники', regular, _getRoleColor(GroupRole.member, theme)),
        ],
      ),
    );
  }

  Widget _buildRoleSection(String title, List<GroupMember> members, Color roleColor) {
    final theme = Theme.of(context);
    
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: roleColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$title (${members.length})',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (members.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'Нет пользователей',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              )
            else
              ...members.map((m) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: roleColor.withOpacity(0.2),
                      backgroundImage: m.avatarUrl != null
                          ? NetworkImage(m.avatarUrl!)
                          : null,
                      child: m.avatarUrl == null
                          ? Text(
                              m.displayName.isNotEmpty ? m.displayName[0] : '?',
                              style: TextStyle(color: roleColor),
                            )
                          : null,
                      radius: 16,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.displayName,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (m.userId.isNotEmpty)
                            Text(
                              m.userId,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
          ],
        ),
      ),
    );
  }

  Widget _buildBanListTab() {
    final theme = Theme.of(context);
    final banned = _currentGroup?.bannedMembers ?? [];
    
    if (banned.isEmpty) {
      return Center(
        child: Text(
          'Нет забаненных пользователей',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: List.generate(banned.length, (index) {
          final member = banned[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Colors.red.withOpacity(0.05),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.red.withOpacity(0.2),
                backgroundImage: member.avatarUrl != null
                    ? NetworkImage(member.avatarUrl!)
                    : null,
                child: member.avatarUrl == null
                    ? Text(member.displayName.isNotEmpty ? member.displayName[0] : '?')
                    : null,
              ),
              title: Text(
                member.displayName,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: Colors.red,
                ),
              ),
              subtitle: const Text('Забанен'),
              trailing: IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                onPressed: () async {
                  try {
                    await _groupService.unbanUser(widget.roomId, member.userId);
                    await _loadGroupData();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Пользователь разбанен')),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка: $e')),
                    );
                  }
                },
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDeleteTab() {
    final theme = Theme.of(context);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            color: Colors.red.withOpacity(0.1),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.warning_rounded, color: Colors.red, size: 40),
                  ),
                  const SizedBox(height: 16),
                Text(
                  'Удалить группу',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.red,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Это действие НЕОБРАТИМО. Все сообщения и данные группы будут полностью удалены и не смогут быть восстановлены.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () => _showDeleteConfirmation(),
                    icon: const Icon(Icons.delete_forever),
                    label: const Text(
                      'Удалить группу',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRoleDialog(GroupMember member) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Изменить роль'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<GroupRole>(
              title: const Text('Администратор'),
              value: GroupRole.admin,
              groupValue: member.role,
              onChanged: (role) async {
                Navigator.pop(context);
                if (role != null) {
                  try {
                    await _groupService.setUserRole(
                      widget.roomId,
                      member.userId,
                      role,
                    );
                    await _loadGroupData();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ошибка: $e')),
                      );
                    }
                  }
                }
              },
            ),
            RadioListTile<GroupRole>(
              title: const Text('Участник'),
              value: GroupRole.member,
              groupValue: member.role,
              onChanged: (role) async {
                Navigator.pop(context);
                if (role != null) {
                  try {
                    await _groupService.setUserRole(
                      widget.roomId,
                      member.userId,
                      role,
                    );
                    await _loadGroupData();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ошибка: $e')),
                      );
                    }
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showFreezeDialog(GroupMember member) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Заморозить пользователя'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in [
              MapEntry('1 час', Duration(hours: 1)),
              MapEntry('1 день', Duration(days: 1)),
              MapEntry('7 дней', Duration(days: 7)),
            ])
              ListTile(
                title: Text(entry.key),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    await _groupService.freezeUser(
                      widget.roomId,
                      member.userId,
                      duration: entry.value,
                    );
                    await _loadGroupData();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ошибка: $e')),
                      );
                    }
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _banUser(GroupMember member) async {
    try {
      await _groupService.banUser(widget.roomId, member.userId);
      await _loadGroupData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пользователь забанен')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  Future<void> _kickUser(GroupMember member) async {
    try {
      await _groupService.kickUser(widget.roomId, member.userId);
      await _loadGroupData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пользователь исключен')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Подтвердить удаление'),
        content: const Text('Вы уверены? Это действие необратимо.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _groupService.deleteGroup(widget.roomId);
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Группа удалена')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка: $e')),
                  );
                }
              }
            },
            child: const Text('Удалить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) {
      return Colors.grey.shade300;
    }
    try {
      final colorString = hexColor.replaceAll('#', '');
      return Color(int.parse('FF$colorString', radix: 16));
    } catch (_) {
      return Colors.grey.shade300;
    }
  }

  Color _getRoleColor(GroupRole role, ThemeData theme) {
    switch (role) {
      case GroupRole.owner:
        return Colors.red;
      case GroupRole.admin:
        return Colors.orange;
      case GroupRole.member:
        return theme.colorScheme.primary;
      case GroupRole.guest:
        return Colors.grey;
    }
  }
}
