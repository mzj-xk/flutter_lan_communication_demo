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
}

enum MessageType { heartbeat, broadcast, private }
