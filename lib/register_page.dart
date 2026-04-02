import 'package:flutter/material.dart';
import 'package:flutter_lan_demo/lan_device_page.dart';
import 'package:flutter_lan_demo/app_state.dart';
import 'package:flutter_lan_demo/models/device.dart';
import 'package:uuid/uuid.dart';

class RegisterPage extends StatelessWidget {
  RegisterPage({super.key});

  final TextEditingController _textController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('注册页')),
      body: Column(
        children: [
          TextField(
            controller: _textController,
            decoration: InputDecoration(labelText: '主机名'),
          ),
          ElevatedButton(
            onPressed: () {
              final device = Device(
                hostName: _textController.text,
                deviceId: Uuid().v4(),
              );
              AppState.instance.myDevice = device;
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => LanDevicePage()),
              );
            },
            child: const Text('注册'),
          ),
        ],
      ),
    );
  }
}
