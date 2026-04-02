import 'package:flutter_lan_demo/models/device.dart';

class AppState {
  static final AppState instance = AppState._();

  AppState._();

  factory AppState() => instance;

  Device? myDevice;
}
