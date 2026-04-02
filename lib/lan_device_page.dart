import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_lan_demo/app_state.dart';
import 'package:flutter_lan_demo/constants.dart';
import 'package:flutter_lan_demo/models/device.dart';
import 'package:flutter_lan_demo/models/message.dart';

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
  final TextEditingController _textController = TextEditingController();

  final List<Message> _messages = [];

  String _currentLeaderId =
      AppState.instance.myDevice?.deviceId ?? ''; // 默认自己是leader

  bool get _isLeader =>
      _currentLeaderId == AppState.instance.myDevice?.deviceId;

  // TCP：连接 leader（非 leader 设备作为 client）
  Socket? _leaderSocket;
  StreamSubscription<String>? _leaderLineSub;
  Timer? _tcpReconnectTimer;
  bool _tcpConnecting = false;
  String? _connectedLeaderId;

  // TCP：Leader Server 以及客户端路由表
  ServerSocket? _tcpServer;
  final Map<String, Socket> _leaderClientSockets = {}; // deviceId -> Socket
  final Map<Socket, String> _socketToDeviceId = {}; // Socket -> deviceId

  // Leader 变化/连接未就绪时的待发送队列
  final Queue<Message> _pendingToLeader = Queue<Message>();

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
    _leaderLineSub?.cancel();
    _leaderLineSub = null;
    _leaderSocket?.destroy();
    _leaderSocket = null;
    _tcpReconnectTimer?.cancel();
    _tcpReconnectTimer = null;

    // TCP leader server 清理
    _tcpServer?.close();
    _tcpServer = null;
    for (final s in _leaderClientSockets.values) {
      s.destroy();
    }
    _leaderClientSockets.clear();
    _socketToDeviceId.clear();

    _pendingToLeader.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = _devices.values.toList();
    return Scaffold(
      appBar: AppBar(
        title: Text('局域网设备 当前设备为: ${AppState.instance.myDevice?.hostName}'),
      ),

      /// 安全区域内
      body: SafeArea(
        child: Column(
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
                        SizedBox(width: 10),
                        Text(
                          device.deviceId == _currentLeaderId
                              ? 'leader'
                              : 'client',
                          style: TextStyle(fontSize: 20),
                        ),
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
            SizedBox(
              height: 300,
              child: ListView.builder(
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return Row(
                    children: [
                      if (message.messageType == MessageType.broadcast)
                        Text('广播消息'),
                      SizedBox(width: 10),
                      Text('sender: ${message.sender}'),
                      SizedBox(width: 10),
                      Text(message.content ?? ''),
                    ],
                  );
                },
              ),
            ),
            // 输入框
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(labelText: '输入消息'),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    sendBroadcastTcp(_textController.text);
                    _textController.clear();
                  },
                  child: Text('发送广播消息'),
                ),
                // ElevatedButton(onPressed: () {}, child: Text('发送私密消息')),
              ],
            ),
          ],
        ),
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
      // debugPrint('discoverHeartbeatDevices: $message from ${datagram.address}');

      /// 解析消息, 如果消息是心跳包, 则更新设备在线状态
      try {
        final decoded = jsonDecode(message);
        if (decoded is! Map<String, dynamic>) return;

        final msg = Message.fromJson(decoded);
        if (msg.messageType != MessageType.heartbeat) return;

        if (msg.senderDeviceId.isEmpty) return;

        final existing = _devices[msg.senderDeviceId];

        if (existing == null) {
          _devices[msg.senderDeviceId] = Device(
            hostName: msg.sender,
            deviceId: msg.senderDeviceId,
            ipAddress: datagram.address.address,
            isOnline: true,
            lastSeen: now,
          );
        } else {
          existing.isOnline = true;
          existing.lastSeen = now;
        }

        if (!mounted) return;
        maybeUpdateLeader();
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

      setState(() {});
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

    final myDevice = AppState.instance.myDevice;
    if (myDevice == null) return;
    if (myDevice.deviceId.isEmpty) return;

    final msg = Message(
      connectionType: ConnectionType.udp,
      messageType: MessageType.heartbeat,
      sender: myDevice.hostName,
      senderDeviceId: myDevice.deviceId,
    );

    final payload = utf8.encode(jsonEncode(msg.toJson()));

    // debugPrint('sendHeartbeatUdp: $msg');

    final broadcast = InternetAddress(broadcastAddress);
    socket.send(payload, broadcast, heartbeatPort);
  }

  /// 排序 uuid 返回最小的 uuid
  String? computeLeaderId() {
    final onlineIds = _devices.values
        .where((d) => d.isOnline)
        .map((d) => d.deviceId);
    if (onlineIds.isEmpty) return null;
    final leaderId = onlineIds.reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
    return leaderId;
  }

  void maybeUpdateLeader() {
    final newLeaderId = computeLeaderId();
    if (newLeaderId == null) return;

    if (newLeaderId == _currentLeaderId) return;

    _currentLeaderId = newLeaderId;
    connectToLeaderTcp();
  }

  /// 连接上 leader 的 TCP 端口
  void connectToLeaderTcp() {
    // leader：启动 TCP Server + 维护客户端路由表
    if (_isLeader) {
      // 清理 client 连接相关
      _tcpReconnectTimer?.cancel();
      _tcpReconnectTimer = null;
      _leaderLineSub?.cancel();
      _leaderLineSub = null;
      _leaderSocket?.destroy();
      _leaderSocket = null;
      _connectedLeaderId = null;
      _tcpConnecting = false;

      _pendingToLeader.clear();
      startLeaderTcpServer();
      return;
    }

    // 非 leader：关闭/清理 leader server（如果之前曾经是 leader）
    _tcpServer?.close();
    _tcpServer = null;
    _leaderClientSockets.forEach((_, s) => s.destroy());
    _leaderClientSockets.clear();
    _socketToDeviceId.clear();
    _pendingToLeader.clear();

    final myDevice = AppState.instance.myDevice;
    if (myDevice == null || myDevice.deviceId.isEmpty) return;
    final leaderId = _currentLeaderId;
    if (leaderId.isEmpty) return;

    // 已经连接到同一个 leader：不重复连接
    if (_leaderSocket != null && _connectedLeaderId == leaderId) return;

    // 还没断开旧连接就试图重连：等待后续逻辑，避免并发 connect
    if (_tcpConnecting) return;
    _tcpConnecting = true;

    // 如果 leader 变化，先清理旧连接
    _tcpReconnectTimer?.cancel();
    _tcpReconnectTimer = null;
    _leaderLineSub?.cancel();
    _leaderLineSub = null;
    _leaderSocket?.destroy();
    _leaderSocket = null;
    _connectedLeaderId = null;

    final leaderDevice = _devices[leaderId];
    final leaderIp = leaderDevice?.ipAddress ?? '';
    if (leaderIp.isEmpty) {
      _tcpConnecting = false;
      _tcpReconnectTimer = Timer(
        const Duration(seconds: 2),
        connectToLeaderTcp,
      );
      return;
    }

    Socket.connect(leaderIp, dataPort)
        .timeout(const Duration(seconds: 3))
        .then((socket) {
          // leaderId 在连接过程中可能变更，做一次一致性校验
          if (_currentLeaderId != leaderId || _isLeader) {
            socket.destroy();
            return;
          }

          _leaderSocket = socket;
          _connectedLeaderId = leaderId;
          _tcpConnecting = false;

          // 接收分帧：每条消息以 '\n' 结尾
          _leaderLineSub = socket
              .map((bytes) => utf8.decode(bytes))
              .transform(const LineSplitter())
              .listen(
                (line) {
                  final trimmed = line.trim();
                  if (trimmed.isEmpty) return;

                  try {
                    final decoded = jsonDecode(trimmed);
                    if (decoded is! Map<String, dynamic>) return;

                    final msg = Message.fromJson(decoded);
                    if (msg.messageType == MessageType.broadcast) {
                      debugPrint('TCP broadcast received: ${msg.content}');
                      // 如果广播内容是“我自己发的”，leader 理论上不会转发给我
                      // 这里做兜底，避免重复显示
                      if (msg.senderDeviceId == myDevice.deviceId) return;
                    } else if (msg.messageType == MessageType.private) {
                      // debugPrint('TCP private received: ${msg.content}');
                    }
                  } catch (_) {
                    // 忽略非 JSON 包
                  }
                },
                onError: (_) {
                  _leaderSocket?.destroy();
                  _leaderSocket = null;
                  _leaderLineSub?.cancel();
                  _leaderLineSub = null;
                  _connectedLeaderId = null;
                  _tcpConnecting = false;

                  _tcpReconnectTimer = Timer(
                    const Duration(seconds: 2),
                    connectToLeaderTcp,
                  );
                },
                onDone: () {
                  _leaderSocket?.destroy();
                  _leaderSocket = null;
                  _leaderLineSub?.cancel();
                  _leaderLineSub = null;
                  _connectedLeaderId = null;
                  _tcpConnecting = false;

                  _tcpReconnectTimer = Timer(
                    const Duration(seconds: 2),
                    connectToLeaderTcp,
                  );
                },
                cancelOnError: true,
              );

          // 握手/身份绑定：发一条消息给 leader（复用 heartbeat 类型）
          final hello = Message(
            connectionType: ConnectionType.tcp,
            messageType: MessageType.heartbeat,
            sender: myDevice.hostName,
            senderDeviceId: myDevice.deviceId,
          );
          socket.write('${jsonEncode(hello.toJson())}\n');

          // leader 准备好后 flush 缓存消息
          while (_pendingToLeader.isNotEmpty) {
            final pending = _pendingToLeader.removeFirst();
            socket.write('${jsonEncode(pending.toJson())}\n');
          }
        })
        .catchError((_) {
          _leaderSocket?.destroy();
          _leaderSocket = null;
          _leaderLineSub?.cancel();
          _leaderLineSub = null;
          _connectedLeaderId = null;
          _tcpConnecting = false;

          _tcpReconnectTimer = Timer(
            const Duration(seconds: 2),
            connectToLeaderTcp,
          );
        });
  }

  /// leader 启动 TCP server：接收客户端连接并转发 broadcast/private
  void startLeaderTcpServer() {
    if (_tcpServer != null) return;

    ServerSocket.bind(InternetAddress.anyIPv4, dataPort)
        .then((server) {
          _tcpServer = server;

          server.listen((client) {
            handleLeaderClientSocket(client);
          }, onError: (_) {});
        })
        .catchError((_) {
          _tcpServer = null;
          _tcpReconnectTimer?.cancel();
          _tcpReconnectTimer = Timer(
            const Duration(seconds: 2),
            connectToLeaderTcp,
          );
        });
  }

  /// 处理 leader 接收到的一个 TCP client 连接
  void handleLeaderClientSocket(Socket client) {
    final socket = client;

    late final StreamSubscription<String> sub;
    sub = socket
        .map((bytes) => utf8.decode(bytes))
        .transform(const LineSplitter())
        .listen(
          (line) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) return;

            try {
              final decoded = jsonDecode(trimmed);
              if (decoded is! Map<String, dynamic>) return;

              final msg = Message.fromJson(decoded);
              final senderDeviceId = msg.senderDeviceId;
              if (senderDeviceId.isEmpty) return;

              if (msg.messageType == MessageType.heartbeat) {
                _socketToDeviceId[socket] = senderDeviceId;
                _leaderClientSockets[senderDeviceId] = socket;
                return;
              }

              if (msg.messageType == MessageType.broadcast) {
                // leader 广播：逐个发给已连接的非自己设备（遍历快照避免并发修改）
                final snapshot = _leaderClientSockets.entries.toList();
                for (final entry in snapshot) {
                  final deviceId = entry.key;
                  final s = entry.value;
                  if (deviceId == msg.senderDeviceId) continue; // 不包括自己
                  s.write('${jsonEncode(msg.toJson())}\n');
                }
                return;
              }

              if (msg.messageType == MessageType.private) {
                final targetId = msg.receiverDeviceId;
                if (targetId == null || targetId.isEmpty) return;

                final targetSocket = _leaderClientSockets[targetId];
                if (targetSocket == null) return;
                targetSocket.write('${jsonEncode(msg.toJson())}\n');
                return;
              }
            } catch (_) {
              // 忽略无效包
            }
          },
          onError: (_) {},
          onDone: () {
            final deviceId = _socketToDeviceId[socket];
            if (deviceId != null) {
              _leaderClientSockets.remove(deviceId);
            }
            _socketToDeviceId.remove(socket);
            sub.cancel();
            socket.destroy();
          },
          cancelOnError: false,
        );
  }

  /// 发送广播消息：leader 直接转发；非 leader 发给 leader
  void sendBroadcastTcp(String content) {
    final myDevice = AppState.instance.myDevice;
    if (myDevice == null || myDevice.deviceId.isEmpty) return;

    final msg = Message(
      connectionType: ConnectionType.tcp,
      messageType: MessageType.broadcast,
      sender: myDevice.hostName,
      senderDeviceId: myDevice.deviceId,
      content: content,
    );

    if (_isLeader) {
      // leader 广播：逐个发给已连接的非自己设备（遍历快照避免并发修改）
      final snapshot = _leaderClientSockets.entries.toList();
      for (final entry in snapshot) {
        final deviceId = entry.key;
        final s = entry.value;
        if (deviceId == myDevice.deviceId) continue;
        s.write('${jsonEncode(msg.toJson())}\n');
      }
      return;
    }

    if (_leaderSocket == null) {
      if (_pendingToLeader.length < 100) _pendingToLeader.addLast(msg);
      return;
    }
    _leaderSocket!.write('${jsonEncode(msg.toJson())}\n');
  }

  /// 发送私密消息：leader 直接转发；非 leader 发给 leader
  void sendPrivateTcp(String receiverDeviceId, String content) {
    final myDevice = AppState.instance.myDevice;
    if (myDevice == null || myDevice.deviceId.isEmpty) return;

    final msg = Message(
      connectionType: ConnectionType.tcp,
      messageType: MessageType.private,
      sender: myDevice.hostName,
      senderDeviceId: myDevice.deviceId,
      receiverDeviceId: receiverDeviceId,
      content: content,
    );

    if (_isLeader) {
      final targetSocket = _leaderClientSockets[receiverDeviceId];
      targetSocket?.write('${jsonEncode(msg.toJson())}\n');
      return;
    }

    if (_leaderSocket == null) {
      if (_pendingToLeader.length < 100) _pendingToLeader.addLast(msg);
      return;
    }
    _leaderSocket!.write('${jsonEncode(msg.toJson())}\n');
  }
}
