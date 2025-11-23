// Enum для ролей в группе
enum GroupRole {
  owner,    // Владелец (может делать всё)
  admin,    // Администратор (может приглашать, исключать, замораживать)
  member,   // Обычный участник
  guest,    // Гость (ограниченные права)
}

// Enum для статуса заморозки
enum FreezeStatus {
  active,      // Активен
  frozen,      // Заморожен
  banned,      // Забанен
}

// Enum для видимости группы
enum GroupVisibility {
  private,   // Приватная (только по приглашению)
  public,    // Публичная (видна всем)
}

// Модель участника группы
class GroupMember {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final GroupRole role;
  final FreezeStatus status;
  final DateTime? frozenUntil;  // null = бесконечно
  final String? freezeReason;
  final DateTime joinedAt;
  final bool canReceiveInvites; // Настройка пользователя: может ли получать приглашения

  GroupMember({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.role,
    this.status = FreezeStatus.active,
    this.frozenUntil,
    this.freezeReason,
    required this.joinedAt,
    this.canReceiveInvites = true,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String? ?? 'Unknown',
      avatarUrl: json['avatar_url'] as String?,
      role: GroupRole.values.firstWhere(
        (e) => e.toString() == 'GroupRole.${json['role']}',
        orElse: () => GroupRole.member,
      ),
      status: FreezeStatus.values.firstWhere(
        (e) => e.toString() == 'FreezeStatus.${json['status']}',
        orElse: () => FreezeStatus.active,
      ),
      frozenUntil: json['frozen_until'] != null ? DateTime.parse(json['frozen_until']) : null,
      freezeReason: json['freeze_reason'] as String?,
      joinedAt: DateTime.parse(json['joined_at'] as String),
      canReceiveInvites: json['can_receive_invites'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'role': role.toString().split('.').last,
      'status': status.toString().split('.').last,
      'frozen_until': frozenUntil?.toIso8601String(),
      'freeze_reason': freezeReason,
      'joined_at': joinedAt.toIso8601String(),
      'can_receive_invites': canReceiveInvites,
    };
  }

  GroupMember copyWith({
    String? userId,
    String? displayName,
    String? avatarUrl,
    GroupRole? role,
    FreezeStatus? status,
    DateTime? frozenUntil,
    String? freezeReason,
    DateTime? joinedAt,
    bool? canReceiveInvites,
  }) {
    return GroupMember(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      status: status ?? this.status,
      frozenUntil: frozenUntil ?? this.frozenUntil,
      freezeReason: freezeReason ?? this.freezeReason,
      joinedAt: joinedAt ?? this.joinedAt,
      canReceiveInvites: canReceiveInvites ?? this.canReceiveInvites,
    );
  }
}

// Модель приглашения в группу
class GroupInvite {
  final String inviteCode;
  final String roomId;
  final String createdBy;  // userId администратора/владельца
  final DateTime createdAt;
  final int maxUses;  // -1 = неограниченно
  final int currentUses;
  final bool isActive;
  final DateTime? expiresAt;

  GroupInvite({
    required this.inviteCode,
    required this.roomId,
    required this.createdBy,
    required this.createdAt,
    this.maxUses = -1,
    this.currentUses = 0,
    this.isActive = true,
    this.expiresAt,
  });

  factory GroupInvite.fromJson(Map<String, dynamic> json) {
    return GroupInvite(
      inviteCode: json['invite_code'] as String,
      roomId: json['room_id'] as String,
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      maxUses: json['max_uses'] as int? ?? -1,
      currentUses: json['current_uses'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'invite_code': inviteCode,
      'room_id': roomId,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'max_uses': maxUses,
      'current_uses': currentUses,
      'is_active': isActive,
      'expires_at': expiresAt?.toIso8601String(),
    };
  }
}

// Модель группы
class GroupRoom {
  final String roomId;
  final String name;
  final String? description;
  final String? avatarUrl;
  final GroupVisibility visibility;
  final GroupRole currentUserRole;
  final int memberCount;
  final bool showMessageHistory;  // Показывать ли историю сообщений новым пользователям
  final String? backgroundColor;  // HEX цвет фона чата
  final String? backgroundImageUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<GroupMember> members;  // Для локального кэша
  final List<GroupMember> bannedMembers;
  final List<GroupInvite> invites;

  GroupRoom({
    required this.roomId,
    required this.name,
    this.description,
    this.avatarUrl,
    this.visibility = GroupVisibility.private,
    required this.currentUserRole,
    this.memberCount = 0,
    this.showMessageHistory = false,
    this.backgroundColor,
    this.backgroundImageUrl,
    required this.createdAt,
    required this.updatedAt,
    this.members = const [],
    this.bannedMembers = const [],
    this.invites = const [],
  });

  factory GroupRoom.fromJson(Map<String, dynamic> json) {
    return GroupRoom(
      roomId: json['room_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      visibility: GroupVisibility.values.firstWhere(
        (e) => e.toString() == 'GroupVisibility.${json['visibility']}',
        orElse: () => GroupVisibility.private,
      ),
      currentUserRole: GroupRole.values.firstWhere(
        (e) => e.toString() == 'GroupRole.${json['current_user_role']}',
        orElse: () => GroupRole.member,
      ),
      memberCount: json['member_count'] as int? ?? 0,
      showMessageHistory: json['show_message_history'] as bool? ?? false,
      backgroundColor: json['background_color'] as String?,
      backgroundImageUrl: json['background_image_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      members: (json['members'] as List<dynamic>?)?.map((m) => GroupMember.fromJson(m as Map<String, dynamic>)).toList() ?? [],
      bannedMembers: (json['banned_members'] as List<dynamic>?)?.map((m) => GroupMember.fromJson(m as Map<String, dynamic>)).toList() ?? [],
      invites: (json['invites'] as List<dynamic>?)?.map((i) => GroupInvite.fromJson(i as Map<String, dynamic>)).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'room_id': roomId,
      'name': name,
      'description': description,
      'avatar_url': avatarUrl,
      'visibility': visibility.toString().split('.').last,
      'current_user_role': currentUserRole.toString().split('.').last,
      'member_count': memberCount,
      'show_message_history': showMessageHistory,
      'background_color': backgroundColor,
      'background_image_url': backgroundImageUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'members': members.map((m) => m.toJson()).toList(),
      'banned_members': bannedMembers.map((m) => m.toJson()).toList(),
      'invites': invites.map((i) => i.toJson()).toList(),
    };
  }

  GroupRoom copyWith({
    String? roomId,
    String? name,
    String? description,
    String? avatarUrl,
    GroupVisibility? visibility,
    GroupRole? currentUserRole,
    int? memberCount,
    bool? showMessageHistory,
    String? backgroundColor,
    String? backgroundImageUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<GroupMember>? members,
    List<GroupMember>? bannedMembers,
    List<GroupInvite>? invites,
  }) {
    return GroupRoom(
      roomId: roomId ?? this.roomId,
      name: name ?? this.name,
      description: description ?? this.description,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      visibility: visibility ?? this.visibility,
      currentUserRole: currentUserRole ?? this.currentUserRole,
      memberCount: memberCount ?? this.memberCount,
      showMessageHistory: showMessageHistory ?? this.showMessageHistory,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundImageUrl: backgroundImageUrl ?? this.backgroundImageUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      members: members ?? this.members,
      bannedMembers: bannedMembers ?? this.bannedMembers,
      invites: invites ?? this.invites,
    );
  }

  // Проверка, может ли текущий пользователь выполнять действие
  bool canManageMembers() => currentUserRole == GroupRole.owner || currentUserRole == GroupRole.admin;
  bool canBanMembers() => currentUserRole == GroupRole.owner;
  bool canDeleteRoom() => currentUserRole == GroupRole.owner;
  bool canChangeBackground() => canManageMembers();
  bool canChangeSettings() => canManageMembers();
  bool canInviteMembers() => currentUserRole == GroupRole.owner || currentUserRole == GroupRole.admin;
}
