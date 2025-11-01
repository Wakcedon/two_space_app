// Message model for chat messages

class MessageModel {
  final String id;
  final String chatId;
  final String fromUserId;
  final String fromName;
  final String? fromAvatarUrl;
  final String text;
  final int createdAt;
  final List<String> reactions; // simple list of emoji codes
  final List<String> deliveredTo;
  final List<String> readBy;
  final String? replyToMessageId;
  final Map<String, dynamic>? replyToPreview; // {fromName, text}
  final String? mediaFileId;

  MessageModel({
    required this.id,
    required this.chatId,
    required this.fromUserId,
    required this.fromName,
    this.fromAvatarUrl,
    required this.text,
    required this.createdAt,
    this.reactions = const [],
    this.deliveredTo = const [],
    this.readBy = const [],
    this.replyToMessageId,
    this.replyToPreview,
    this.mediaFileId,
  });

  factory MessageModel.fromMap(Map<String, dynamic> m) {
    return MessageModel(
      id: m['\$id']?.toString() ?? m['id']?.toString() ?? '',
      chatId: m['chatId']?.toString() ?? '',
      fromUserId: m['fromUserId']?.toString() ?? '',
      fromName: m['fromName']?.toString() ?? '',
      fromAvatarUrl: m['fromAvatarUrl']?.toString(),
      text: m['text']?.toString() ?? '',
      createdAt: (m['createdAt'] is int) ? m['createdAt'] as int : DateTime.tryParse(m['createdAt']?.toString() ?? '')?.millisecondsSinceEpoch ?? 0,
  reactions: (m['reactions'] is List) ? List<String>.from(m['reactions']) : <String>[],
  deliveredTo: (m['deliveredTo'] is List) ? List<String>.from(m['deliveredTo']) : <String>[],
  readBy: (m['readBy'] is List) ? List<String>.from(m['readBy']) : <String>[],
      replyToMessageId: m['replyToMessageId']?.toString(),
      replyToPreview: (m['replyToPreview'] is Map) ? Map<String, dynamic>.from(m['replyToPreview']) : null,
      mediaFileId: m['mediaFileId']?.toString(),
    );
  }
}
