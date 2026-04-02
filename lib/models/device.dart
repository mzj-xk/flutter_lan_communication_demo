class Device {
  final String hostName;
  final String deviceId;

  /// 对端 IP（由 UDP 心跳接收时的 datagram.address 记录）
  String ipAddress;

  /// TCP 监听端口（可在后续协议中填充；当前先保留字段）
  int tcpPort;

  bool isOnline;
  DateTime lastSeen;
  Device({
    required this.hostName,
    required this.deviceId,
    this.ipAddress = '',
    this.tcpPort = 0,
    this.isOnline = true,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();
}
