# 局域网设备通信 Demo 总结

## 项目背景

餐厅多台点餐设备场景：每台设备有本地数据库记录库存，数据库定期与服务器同步。下单时通过局域网通信通知其他设备库存变化，实现本地库存的实时更新。

## 技术方案

### 设备发现：UDP 广播心跳

- 所有设备通过 UDP 广播（端口 8766）定时发送心跳包（间隔 3 秒）
- 广播地址 `255.255.255.255`，局域网内所有设备均可接收
- 收到心跳后记录设备信息（主机名、deviceId、IP 地址）并标记为在线
- 超过 3 次心跳间隔未收到心跳的设备标记为离线

### Leader 选举

- 所有在线设备的 deviceId（UUID）排序，取最小值作为 Leader
- Leader 负责启动 TCP Server，接收其他设备的连接
- 非 Leader 设备作为 TCP Client 连接到 Leader
- Leader 离线时自动重新选举，客户端自动重连新 Leader

### 消息通信：TCP 中转（星型拓扑）

所有消息通过 Leader 中转，使用 TCP 保证可靠传输，每条消息以 JSON 格式编码，`\n` 分帧。

#### 广播消息

- 发送者将消息发给 Leader
- Leader 转发给所有已连接的客户端（排除发送者）
- 发送者和所有接收者均可在消息列表中看到该消息
- Leader 自身收到广播也会显示

#### 私聊消息

- 发送者将消息发给 Leader，指定 `receiverDeviceId`
- Leader 根据目标 deviceId 转发给对应客户端
- 如果目标是 Leader 自身，则直接显示
- 发送者和接收者均可在消息列表中看到该消息

### 连接容错

- TCP 连接断开后自动重连（2 秒延迟）
- Leader 变更时清理旧连接并建立新连接
- 连接未就绪时消息暂存到待发送队列（上限 100 条），连接建立后自动 flush

## 项目结构

| 文件 | 说明 |
|------|------|
| `lib/main.dart` | 应用入口 |
| `lib/register_page.dart` | 注册页，输入主机名并生成 UUID 作为设备标识 |
| `lib/lan_device_page.dart` | 核心页面，包含设备发现、Leader 选举、TCP 通信、消息收发 |
| `lib/app_state.dart` | 全局状态，存储当前设备信息 |
| `lib/models/device.dart` | 设备模型（主机名、deviceId、IP、在线状态等） |
| `lib/models/message.dart` | 消息模型（连接类型、消息类型、发送者、接收者、内容） |
| `lib/constants.dart` | 常量定义（端口号、心跳间隔、广播地址） |

## 消息类型

| 类型 | 用途 | 传输方式 |
|------|------|----------|
| `heartbeat` | 设备发现与在线检测 | UDP 广播 |
| `broadcast` | 广播消息（如库存变更通知） | TCP 经 Leader 中转 |
| `private` | 私聊消息 | TCP 经 Leader 中转 |
