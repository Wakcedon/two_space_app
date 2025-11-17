class User {
  final String id;
  String name;
  String email;
  Map<String, dynamic> prefs;
  String? avatarUrl;
  String? avatarFileId;
  String? description;
  String? phone;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.prefs,
    this.avatarUrl,
    this.avatarFileId,
    this.description,
    this.phone,
  });

  factory User.fromMap(Map<String, dynamic> map) {
    final prefs = (map['prefs'] is Map) ? Map<String, dynamic>.from(map['prefs']) : <String, dynamic>{};
    final id = (map['\$id'] ?? map['id'])?.toString() ?? '';
    final name = (map['name'] as String?) ?? (prefs['displayName'] as String?) ?? id;
    final email = (map['email'] as String?) ?? '';
    return User(
      id: id,
      name: name,
      email: email,
      prefs: prefs,
      avatarUrl: prefs['avatarUrl'] as String?,
      avatarFileId: prefs['avatarFileId']?.toString(),
      description: prefs['description'] as String?,
      phone: prefs['phone'] as String?,
    );
  }

  /// Backwards-compatible alias used in some places in the codebase.
  factory User.fromJson(Map<String, dynamic> json) => User.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  /// Convenience getter used across the codebase.
  String get displayName {
    if (name.isNotEmpty) return name;
    if (prefs.containsKey('nickname') && (prefs['nickname'] as String?)?.isNotEmpty == true) return '@${prefs['nickname']}';
    if (email.isNotEmpty) return email;
    return id;
  }

  Map<String, dynamic> toMap() {
    return {
      '\$id': id,
      'name': name,
      'email': email,
      'prefs': {
        ...prefs,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (avatarFileId != null) 'avatarFileId': avatarFileId,
        if (description != null) 'description': description,
        if (phone != null) 'phone': phone,
      },
    };
  }

  User copyWith({
    String? id,
    String? name,
    String? email,
    Map<String, dynamic>? prefs,
    String? avatarUrl,
    String? avatarFileId,
    String? description,
    String? phone,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,  
      email: email ?? this.email,
      prefs: prefs ?? Map<String, dynamic>.from(this.prefs),
      avatarUrl: avatarUrl ?? this.avatarUrl,
      avatarFileId: avatarFileId ?? this.avatarFileId,
      description: description ?? this.description,
      phone: phone ?? this.phone,
    );
  }
}
