class Device {
  final String hostName;
  final String deviceId;
  bool isOnline;
  Device({
    required this.hostName,
    required this.deviceId,
    this.isOnline = true,
  });
}
