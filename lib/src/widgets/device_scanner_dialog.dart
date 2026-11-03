import 'dart:async';

import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

import '../heart_rate/heart_rate_controller.dart';
import '../theme/app_theme.dart';

Future<void> showDeviceScanner(
  BuildContext context,
  HeartRateController controller,
) {
  controller.clearError();
  return showDialog<void>(
    context: context,
    builder: (context) => DeviceScannerDialog(controller: controller),
  );
}

class DeviceScannerDialog extends StatefulWidget {
  const DeviceScannerDialog({super.key, required this.controller});

  final HeartRateController controller;

  @override
  State<DeviceScannerDialog> createState() => _DeviceScannerDialogState();
}

class _DeviceScannerDialogState extends State<DeviceScannerDialog> {
  bool _heartRateOnly = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startScan());
    });
  }

  Future<void> _startScan() async {
    await widget.controller.startScan(heartRateOnly: _heartRateOnly);
  }

  Future<void> _changeFilter(bool heartRateOnly) async {
    if (_heartRateOnly == heartRateOnly) {
      return;
    }
    setState(() {
      _heartRateOnly = heartRateOnly;
    });
    await _startScan();
  }

  Future<void> _select(BleDevice device) async {
    await widget.controller.selectDevice(device);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    // A selected device needs its persistent scan; only stop when the user
    // closed the dialog without choosing anything.
    if (widget.controller.selectedDevice == null) {
      unawaited(widget.controller.stopScan(notify: false));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 640,
        height: screenSize.height.clamp(520, 690),
        child: AnimatedBuilder(
          animation: Listenable.merge([
            widget.controller.scanChanges,
            widget.controller.connectionChanges,
          ]),
          builder: (context, child) {
            final devices = widget.controller.scanDevices;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DialogHeader(
                  scanning: widget.controller.isScanning,
                  onRefresh: _startScan,
                  onClose: () => Navigator.of(context).pop(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('标准心率设备'),
                        icon: Icon(Icons.favorite_border, size: 17),
                      ),
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('所有蓝牙设备'),
                        icon: Icon(Icons.bluetooth_searching, size: 17),
                      ),
                    ],
                    selected: {_heartRateOnly},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      unawaited(_changeFilter(selection.first));
                    },
                  ),
                ),
                _ScanSummary(
                  deviceCount: devices.length,
                  scanning: widget.controller.isScanning,
                  heartRateOnly: _heartRateOnly,
                ),
                if (widget.controller.errorMessage case final message?)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: _InlineError(message: message),
                  ),
                const Divider(height: 1),
                Expanded(
                  child: _DeviceList(
                    devices: devices,
                    scanning: widget.controller.isScanning,
                    lastDeviceId: widget.controller.lastDevice?.deviceId,
                    onSelect: _select,
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.controller.bluetoothReady
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth_disabled,
                        size: 16,
                        color: widget.controller.bluetoothReady
                            ? AppColors.mint
                            : AppColors.inkMuted,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.controller.availabilityLabel,
                        style: const TextStyle(
                          color: AppColors.inkMuted,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'BLE Heart Rate Broadcast',
                        style: TextStyle(
                          color: AppColors.inkMuted.withValues(alpha: 0.72),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.scanning,
    required this.onRefresh,
    required this.onClose,
  });

  final bool scanning;
  final Future<void> Function() onRefresh;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 16, 16),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.coralWash,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.monitor_heart_outlined,
              color: AppColors.coral,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('选择心率设备', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  scanning ? '正在搜索附近设备' : '搜索已暂停',
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '重新搜索',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 20),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }
}

class _ScanSummary extends StatelessWidget {
  const _ScanSummary({
    required this.deviceCount,
    required this.scanning,
    required this.heartRateOnly,
  });

  final int deviceCount;
  final bool scanning;
  final bool heartRateOnly;

  @override
  Widget build(BuildContext context) {
    final text = heartRateOnly
        ? '找到 $deviceCount 台心率候选设备'
        : '发现 $deviceCount 台蓝牙设备';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
      child: Row(
        children: [
          if (scanning)
            const SizedBox.square(
              dimension: 13,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: AppColors.coral,
              ),
            )
          else
            const Icon(Icons.radar, color: AppColors.inkMuted, size: 15),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({
    required this.devices,
    required this.scanning,
    required this.lastDeviceId,
    required this.onSelect,
  });

  final List<BleDevice> devices;
  final bool scanning;
  final String? lastDeviceId;
  final Future<void> Function(BleDevice device) onSelect;

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) {
      return Center(
        child: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                scanning ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
                size: 36,
                color: AppColors.inkMuted.withValues(alpha: 0.55),
              ),
              const SizedBox(height: 14),
              Text(
                scanning ? '正在寻找附近的手环' : '暂未发现心率设备',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                scanning
                    ? '请确认手环已开启「运动心率广播」并靠近电脑。'
                    : '可刷新搜索或切换到所有蓝牙设备。小米手环需在'
                          '「设置 → 锻炼 → 心率广播」开启广播后才会对外发送心率。',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.inkMuted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: devices.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final device = devices[index];
        final supportsHeartRate = advertisesHeartRateService(device);
        final isLastDevice = device.deviceId == lastDeviceId;
        final isCachedLastDevice = isLastDevice && device.rssi == null;
        return _DeviceRow(
          device: device,
          supportsHeartRate: supportsHeartRate,
          isLastDevice: isLastDevice,
          isCachedLastDevice: isCachedLastDevice,
          onSelect: () => onSelect(device),
        );
      },
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.supportsHeartRate,
    required this.isLastDevice,
    required this.isCachedLastDevice,
    required this.onSelect,
  });

  final BleDevice device;
  final bool supportsHeartRate;
  final bool isLastDevice;
  final bool isCachedLastDevice;
  final Future<void> Function() onSelect;

  @override
  Widget build(BuildContext context) {
    final name = device.name?.trim();
    final displayName = name == null || name.isEmpty ? '未命名设备' : name;

    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: supportsHeartRate
                    ? AppColors.mintWash
                    : AppColors.paperDeep,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(
                supportsHeartRate ? Icons.favorite_border : Icons.bluetooth,
                size: 19,
                color: supportsHeartRate ? AppColors.mint : AppColors.inkMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (supportsHeartRate) ...[
                        const SizedBox(width: 8),
                        const _SmallBadge(label: '心率'),
                      ],
                      if (isLastDevice) ...[
                        const SizedBox(width: 8),
                        const _SmallBadge(label: '上次使用'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _deviceSubtitle(
                      device,
                      isCachedLastDevice: isCachedLastDevice,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: onSelect,
              icon: Icon(
                isCachedLastDevice ? Icons.refresh : Icons.check_circle_outline,
                size: 16,
              ),
              label: Text(isCachedLastDevice ? '重连' : '选择'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(86, 38),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _deviceSubtitle(BleDevice device, {required bool isCachedLastDevice}) {
    if (isCachedLastDevice) {
      return '上次连接设备，可直接尝试重连  ·  ${device.deviceId}';
    }
    final parts = <String>[];
    if (device.rssi != null) {
      parts.add('${device.rssi} dBm');
    }
    parts.add(device.deviceId);
    return parts.join('  ·  ');
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.mintWash,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.mint,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.coralWash,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.coralDark, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.coralDark,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
