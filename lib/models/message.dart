class Message {
  final ConnectionType connectionType;
  final MessageType messageType;
  final String sender;
  final String senderDeviceId;
  final String? receiver;
  final String? receiverDeviceId;
  final String? content;

  Message({
    required this.connectionType,
    this.messageType = MessageType.heartbeat,
    required this.sender,
    required this.senderDeviceId,
    this.receiver,
    this.receiverDeviceId,
    this.content,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    final connectionTypeStr = (json['connectionType'] ?? '').toString();
    final messageTypeStr = (json['messageType'] ?? '').toString();

    final connectionType =
        ConnectionType.values
            .where((e) => e.name == connectionTypeStr)
            .isNotEmpty
        ? ConnectionType.values.firstWhere((e) => e.name == connectionTypeStr)
        : ConnectionType.udp;

    final messageType =
        MessageType.values.where((e) => e.name == messageTypeStr).isNotEmpty
        ? MessageType.values.firstWhere((e) => e.name == messageTypeStr)
        : MessageType.heartbeat;

    return Message(
      connectionType: connectionType,
      messageType: messageType,
      sender: (json['sender'] ?? '').toString(),
      senderDeviceId: (json['senderDeviceId'] ?? '').toString(),
      receiver: json['receiver']?.toString(),
      receiverDeviceId: json['receiverDeviceId']?.toString(),
      content: json['content']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'connectionType': connectionType.name,
      'messageType': messageType.name,
      'sender': sender,
      'senderDeviceId': senderDeviceId,
      'receiver': receiver,
      'receiverDeviceId': receiverDeviceId,
      'content': content,
    };
  }
}

enum ConnectionType { udp, tcp }

enum MessageType { heartbeat, broadcast, private }
