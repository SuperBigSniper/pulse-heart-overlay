# Pulse 心率

使用 Flutter 编写的 macOS / Windows 桌面心率监测工具。应用通过 BLE
扫描、连接支持标准 Heart Rate Service 的手环，实时显示心率、R-R 间期和
本次连接趋势，并让心跳动画随 BPM 改变节奏。

![Pulse app icon](assets/branding/app_icon.svg)

## 功能

- 扫描广播标准心率服务的 BLE 设备，也可切换到全部蓝牙设备。
- 解析心率测量特征的 8 位和 16 位 BPM、传感器接触状态、能量消耗和 R-R
  间期。
- 优先订阅通知，必要时自动改用指示模式。
- 显示当前心率、静息范围、平均心率、数据新鲜度和实时趋势。
- 每次真实心率读数都会保存到本地，可按 1 小时、24 小时、7 天或全部时间
  回看折线图；低/中/高心率区间分别使用独立底色和标记。
- 每次选择设备都会建立独立连接会话；切换设备、断开连接或进入演示模式时
  结束当前会话，历史页可在不同会话之间切换。
- 可点击历史折线中的任意心率点添加、修改或删除备注，备注点会保留在图上，
  应用重启后仍可回看。演示模式的数据不会写入真实历史。
- 心跳收缩、光晕和 ECG 波形的速度由实时心率驱动。
- 游戏角落模式：透明无边框、置顶、只显示心跳动画与心率，适合放在游戏
  画面边缘。
- 提供明确标注的演示模式，无手环时也可检查动画节奏。
- macOS 和 Windows 自适应桌面布局，支持窗口缩放。

## 协议兼容性

默认支持 Bluetooth SIG 标准心率服务：

- Service: `0x180D`
- Measurement characteristic: `0x2A37`

多数开启“心率广播”的运动手环、胸带和心率传感器可以直接使用。只提供厂商
私有蓝牙协议的手环不能由通用扫描直接读取，需要按具体品牌和型号补充协议
实现。

## 工作原理

两端共用 Dart 侧的扫描、缓存、设备选择、心率帧解析、历史记录、断线重试和
持久化逻辑，差异集中在 GATT 建链方式。

### 公共流程

1. 使用 `universal_ble` 扫描广播，在 Dart 层筛选广播 `0x180D`、心率服务
   数据或小米厂商数据的设备，避免系统级服务过滤漏掉设备。
2. 选中设备后使用 `0x180D` 服务、服务数据和小米厂商数据过滤器持续扫描，
   并从中尝试读取 BPM。这样，只发送心率广播的设备无需建立 GATT 也能工作，
   同时避免持续接收无关蓝牙广播。
3. 同时尝试连接标准 Heart Rate Profile，发现 `0x180D` 服务和 `0x2A37`
   测量特征，并优先启用 Notify；Notify 失败时自动改用 Indicate。
4. 广告数据和 `0x2A37` 通知都进入同一个帧解析器，统一生成 BPM、传感器
   接触状态和 R-R 间期。
5. GATT 断开后按 2、4、8、16、32、60 秒退避重连；连接建立期间继续依靠
   广告数据，避免界面停止刷新。
6. 断开后把手环加入搜索页的“上次设备”。部分手环断开后暂不恢复广播，
   此时可直接对已知设备发起 GATT 重连，无需重新开关手环广播。
7. 演示模式保留现有 BLE 会话，只忽略演示期间的真实读数；结束演示后恢复
   原设备的广播或 GATT 通知。

### 本地历史

真实心率点会批量追加到应用支持目录中的
`pulse_heart_rate_points.ndjson`，点位备注单独保存在
`pulse_heart_rate_notes.json`。心率点只追加不重写，备注文件使用临时文件
原子替换，避免长时间记录时反复重写整份历史。文件解析和 JSON 序列化在后台
isolate 中完成。同一秒内的多包广播只保留一个采样点，默认保留最近 30 天且
最多 10 万个点；超期或超量的点在启动或运行期间自动清理，达到上限时按
5% 批量淘汰，避免逐点移动大量数据。
心率低于 60 BPM 显示为低区，60–100 BPM 显示为中区，高于 100 BPM 显示为
高区。

### macOS

macOS 使用 `universal_ble` 的 CoreBluetooth 实现完成扫描、连接、服务发现
和特征订阅。连接成功后先尝试 Notify，失败时通过同一插件订阅 Indicate。
应用需要 `NSBluetoothAlwaysUsageDescription` 和蓝牙沙盒 entitlement，首次
访问时由系统请求蓝牙权限。

### Windows

Windows 的扫描仍使用 `universal_ble`，但 GATT 连接由
`windows/runner/heart_rate_channel.cpp` 通过 WinRT 完成。原生代码只查询
`0x180D` 和 `0x2A37`，不会枚举手环受保护的 HID 服务 `0x1812`，从而避免
因枚举该服务而触发系统绑定或 `AccessDenied`。原生层将连接状态和测量字节
通过 `pulse/heart_rate` MethodChannel 发送给 Dart，随后与 macOS 共用同一
套解析和会话逻辑。

Windows 原生订阅优先写 Notify CCCD；Notify 不可用或写入失败时改试 Indicate。
停止接收或切换设备会先释放旧 GATT 会话，并递增原生订阅代次，使尚未完成的
旧连接回调失效，防止旧设备稍后把连接状态或测量数据写回当前会话。

## 环境

项目使用 Flutter 稳定版 `3.47.9` 和 Dart `3.13.7`。当前机器上的 SDK 位于：

```text
~/development/flutter
```

临时设置命令：

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
```

macOS 需要 Xcode 及蓝牙权限。Windows 需要 Visual Studio 2022 的
“Desktop development with C++”工作负载和 Windows 10/11 SDK。

当前通过 `dependency_overrides` 将 `shared_preferences_foundation` 锁定为
`2.5.7`，以兼容 Xcode 15.3 / Swift 5.10。`2.6.x` 生成的 Swift 代码使用了
该工具链尚不支持的尾随逗号；全部开发环境升级到兼容的 Xcode 后可重新评估
这个锁定。

## 运行

macOS：

```bash
flutter pub get
flutter run -d macos
```

Windows：

```powershell
flutter pub get
flutter run -d windows
```

Windows 发布为便携版 ZIP，解压后直接运行 `heartbeat_monitor.exe`，无需
安装。若连接时出现“拒绝访问”，请先在系统「设置 → 蓝牙和其他设备」中
断开或忽略该手环，并关闭手机或其他电脑上正在占用它的连接应用后重试。

启动时直接进入演示模式：

```bash
flutter run -d macos --dart-define=START_DEMO=true
```

连接设备并收到心率后，点击左侧的“游戏角落模式”。窗口会缩为右上角的
透明心率浮层，默认尺寸为 90×120：

- 拖动浮层可调整位置。
- 拖动任意一个角可分别调整宽度和高度，最小为 10×10，最大可覆盖当前屏幕。
- 鼠标滚轮放在浮层上也可等比例缩放。
- 爱心和 ECG 动画共用节拍，并按真实 BPM 实时播放：
  `50 BPM → 每 1.2 秒一次`、`100 → 每 0.6 秒一次`，中间值连续换算。
- 点击侧栏的设置按钮，可调整心跳速度、爱心大小、心率文字大小以及浮层
  宽度和高度，设置会自动保存。
- 双击浮层或按 `Esc` 恢复完整界面。
- 浮层不会显示连接状态、趋势或其它操作按钮。

## 构建

```bash
flutter build macos --release
flutter build windows --release
```

构建产物位置：

- macOS: `build/macos/Build/Products/Release/Pulse.app`
- Windows: `build/windows/x64/runner/Release/heartbeat_monitor.exe`

`.github/workflows/build-desktop.yml` 可在 Windows 和 macOS 的 GitHub
Actions runner 上分别构建发布版。Windows 发布版不能在 macOS 主机上原生
编译。推送到 `main`、创建 `v*` 标签或手动触发工作流时，GitHub Actions
会运行分析、测试和双平台发布构建。创建版本标签后，两个平台压缩包还会自动
附加到 GitHub Release。

## 验证

```bash
flutter analyze
flutter test
```

测试覆盖标准心率帧解析、BPM 与动画周期映射、本地历史持久化与备注、
历史折线采样、心跳曲线和动画组件渲染。真实设备读数仍需要在目标 macOS /
Windows 机器上连接手环验证。

## 目录

```text
lib/src/heart_rate/     BLE 连接、协议解析、会话状态
lib/src/screens/        桌面监测界面
lib/src/widgets/        心跳动画、趋势图、设备扫描
lib/src/theme/          Material 3 主题
assets/branding/        应用图标源文件
```
