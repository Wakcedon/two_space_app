// Forwarded message model
class ForwardedMessage {
  final String messageId;
  final String senderId;
  final String senderName;
  final String sourceChat;
  final String content;
  final DateTime timestamp;

  ForwardedMessage({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.sourceChat,
    required this.content,
    required this.timestamp,
  });

  String get forwardedFrom => 'Переслано от $senderName из $sourceChat';
}
