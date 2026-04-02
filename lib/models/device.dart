class Device {
  final String hostName;
  final String deviceId;
  bool isOnline;
  DateTime lastSeen;
  Device({
    required this.hostName,
    required this.deviceId,
    this.isOnline = true,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();
}
