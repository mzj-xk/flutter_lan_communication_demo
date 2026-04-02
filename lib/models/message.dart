class Message {
  final MessageType messageType;
  final String sender;
  final String senderDeviceId;
  final String? receiver;
  final String? receiverDeviceId;
  final String? content;

  Message({
    this.messageType = MessageType.heartbeat,
    required this.sender,
    required this.senderDeviceId,
    this.receiver,
    this.receiverDeviceId,
    this.content,
  });

  Map<String, dynamic> toJson() {
    return {
      'messageType': messageType.name,
      'sender': sender,
      'senderDeviceId': senderDeviceId,
      'receiver': receiver,
      'receiverDeviceId': receiverDeviceId,
      'content': content,
    };
  }

  static Message fromJson(Map<String, dynamic> json) {
    final typeStr = (json['messageType'] ?? '').toString();
    final parsedType = MessageType.values
        .where((e) => e.name == typeStr)
        .isNotEmpty
        ? MessageType.values.firstWhere((e) => e.name == typeStr)
        : MessageType.heartbeat;

    return Message(
      messageType: parsedType,
      sender: (json['sender'] ?? '').toString(),
      senderDeviceId: (json['senderDeviceId'] ?? '').toString(),
      receiver: json['receiver']?.toString(),
      receiverDeviceId: json['receiverDeviceId']?.toString(),
      content: json['content']?.toString(),
    );
  }
}

enum MessageType { heartbeat, broadcast, private }
