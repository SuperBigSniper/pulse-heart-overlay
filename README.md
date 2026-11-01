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
- 心跳收缩、光晕和 ECG 波形的速度由实时心率驱动。
- 游戏角落模式：无边框、置顶、只显示心率，适合放在游戏画面边缘。
- 提供明确标注的演示模式，无手环时也可检查动画节奏。
- macOS 和 Windows 自适应桌面布局，支持窗口缩放。

## 协议兼容性

默认支持 Bluetooth SIG 标准心率服务：

- Service: `0x180D`
- Measurement characteristic: `0x2A37`

多数开启“心率广播”的运动手环、胸带和心率传感器可以直接使用。只提供厂商
私有蓝牙协议的手环不能由通用扫描直接读取，需要按具体品牌和型号补充协议
实现。

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

启动时直接进入演示模式：

```bash
flutter run -d macos --dart-define=START_DEMO=true
```

连接设备并收到心率后，点击左侧的“游戏角落模式”。窗口会缩为右上角的
168×72 心率浮层：

- 拖动浮层可调整位置。
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

测试覆盖标准心率帧解析、BPM 与动画周期映射、心跳曲线和动画组件渲染。真实
设备读数仍需要在目标 macOS / Windows 机器上连接手环验证。

## 目录

```text
lib/src/heart_rate/     BLE 连接、协议解析、会话状态
lib/src/screens/        桌面监测界面
lib/src/widgets/        心跳动画、趋势图、设备扫描
lib/src/theme/          Material 3 主题
assets/branding/        应用图标源文件
```
