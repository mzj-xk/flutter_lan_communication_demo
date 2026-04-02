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
  final Map<String, Device> _devices = {};
  @override
  void initState() {
    super.initState();
    // 在 initState 中使用 addPostFrameCallback 确保 UI 已构建完成
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await openUdpForHeartbeat();
      startHeartbeat();
      discoverHeartbeatDevices();
    });
  }

  @override
  void dispose() {
    _udpSocket?.close();
    _heartbeatTimer?.cancel();
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

      final message = utf8.decode(datagram.data);
      debugPrint('discoverHeartbeatDevices: $message from ${datagram.address}');

      /// 解析消息, 如果消息是心跳包, 则添加到设备列表
      final messageMap = jsonDecode(message);
      if (messageMap['type'] == 'heartbeat') {
        final device = Device(
          hostName: messageMap['name'] ?? '',
          deviceId: messageMap['deviceId'] ?? '',
        );
        if (!_devices.containsKey(device.deviceId)) {
          _devices[device.deviceId] = device;
        }
        setState(() {});
      }
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
