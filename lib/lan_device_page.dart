import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_lan_demo/app_state.dart';
import 'package:flutter_lan_demo/constants.dart';
import 'package:flutter_lan_demo/models/device.dart';

class LanDevicePage extends StatefulWidget {
  const LanDevicePage({super.key});

  @override
  State<LanDevicePage> createState() => _LanDevicePageState();
}

class _LanDevicePageState extends State<LanDevicePage> {
  RawDatagramSocket? _udpSocket;
  Timer? _heartbeatTimer;
  Timer? _offlineCheckTimer;
  final Map<String, Device> _devices = {};
  @override
  void initState() {
    super.initState();
    // 在 initState 中使用 addPostFrameCallback 确保 UI 已构建完成
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await openUdpForHeartbeat();
      startHeartbeat();
      discoverHeartbeatDevices();
      startOfflineCheck();
    });
  }

  @override
  void dispose() {
    _udpSocket?.close();
    _heartbeatTimer?.cancel();
    _offlineCheckTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = _devices.values.toList();
    return Scaffold(
      appBar: AppBar(
        title: Text('局域网设备 当前设备为: ${AppState.instance.myDevice?.hostName}'),
      ),
      body: Column(
        children: [
          Text('设备列表'),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, index) {
                final device = list[index];
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Text(device.hostName, style: TextStyle(fontSize: 20)),
                      Spacer(),
                      Container(
                        width: 15,
                        height: 15,
                        decoration: BoxDecoration(
                          color: device.isOnline ? Colors.green : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> openUdpForHeartbeat() async {
    _udpSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      heartbeatPort,
      reusePort: true,
    );
    _udpSocket!.broadcastEnabled = true;
  }

  // 发现心跳设备
  void discoverHeartbeatDevices() {
    final socket = _udpSocket;
    if (socket == null) return;

    socket.listen((RawSocketEvent event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;

      final now = DateTime.now();
      final message = utf8.decode(datagram.data);
      debugPrint('discoverHeartbeatDevices: $message from ${datagram.address}');

      /// 解析消息, 如果消息是心跳包, 则更新设备在线状态
      try {
        final messageMap = jsonDecode(message);
        if (messageMap is! Map) return;
        if (messageMap['type'] != 'heartbeat') return;

        final deviceId = (messageMap['deviceId'] ?? '').toString();
        if (deviceId.isEmpty) return;

        final hostName = (messageMap['name'] ?? '').toString();
        final existing = _devices[deviceId];

        if (existing == null) {
          _devices[deviceId] = Device(
            hostName: hostName,
            deviceId: deviceId,
            isOnline: true,
            lastSeen: now,
          );
        } else {
          existing.isOnline = true;
          existing.lastSeen = now;
        }

        if (!mounted) return;
        setState(() {});
      } catch (_) {
        // 非 JSON 或字段异常的包直接忽略，避免 listen 回调中断
      }
    });
  }

  // 离线检测：超过一定时间未收到心跳则标记为离线
  void startOfflineCheck() {
    final offlineTimeout = heartbeatInterval * 3;
    _offlineCheckTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();

      var changed = false;
      _devices.forEach((_, device) {
        final diff = now.difference(device.lastSeen);
        if (device.isOnline && diff > offlineTimeout) {
          device.isOnline = false;
          changed = true;
        }
      });

      if (changed) setState(() {});
    });
  }

  // 通过端口定时发送心跳包
  void startHeartbeat() {
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (timer) {
      sendHeartbeatUdp();
    });
  }

  // 发送心跳包
  void sendHeartbeatUdp() {
    final socket = _udpSocket;
    if (socket == null) return;

    final heartbeat = {
      'type': 'heartbeat',
      'name': AppState.instance.myDevice?.hostName,
      'deviceId': AppState.instance.myDevice?.deviceId,
      'dataPort': dataPort,
    };

    final payload = utf8.encode(jsonEncode(heartbeat));

    debugPrint('sendHeartbeatUdp: $heartbeat');

    final broadcast = InternetAddress(broadcastAddress);
    socket.send(payload, broadcast, heartbeatPort);
  }
}
