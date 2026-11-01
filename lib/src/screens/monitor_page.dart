import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../heart_rate/heart_rate_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/device_scanner_dialog.dart';
import '../widgets/game_overlay_settings_dialog.dart';
import '../widgets/heart_rate_chart.dart';
import '../widgets/heartbeat_visualizer.dart';
import 'game_overlay_settings.dart';

class MonitorPage extends StatelessWidget {
  const MonitorPage({
    super.key,
    required this.controller,
    required this.onEnterGameOverlay,
    required this.overlaySettings,
    required this.onOverlaySettingsChanged,
  });

  final HeartRateController controller;
  final VoidCallback onEnterGameOverlay;
  final GameOverlaySettings overlaySettings;
  final ValueChanged<GameOverlaySettings> onOverlaySettingsChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Scaffold(
          backgroundColor: AppColors.paper,
          body: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 1160) {
                return _WideLayout(
                  controller: controller,
                  onEnterGameOverlay: onEnterGameOverlay,
                  overlaySettings: overlaySettings,
                  onOverlaySettingsChanged: onOverlaySettingsChanged,
                );
              }
              if (constraints.maxWidth >= 760) {
                return _MediumLayout(
                  controller: controller,
                  onEnterGameOverlay: onEnterGameOverlay,
                  overlaySettings: overlaySettings,
                  onOverlaySettingsChanged: onOverlaySettingsChanged,
                );
              }
              return _CompactLayout(
                controller: controller,
                onEnterGameOverlay: onEnterGameOverlay,
                overlaySettings: overlaySettings,
                onOverlaySettingsChanged: onOverlaySettingsChanged,
              );
            },
          ),
        );
      },
    );
  }
}

class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.controller,
    required this.onEnterGameOverlay,
    required this.overlaySettings,
    required this.onOverlaySettingsChanged,
  });

  final HeartRateController controller;
  final VoidCallback onEnterGameOverlay;
  final GameOverlaySettings overlaySettings;
  final ValueChanged<GameOverlaySettings> onOverlaySettingsChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 282,
          child: _Sidebar(
            controller: controller,
            onEnterGameOverlay: onEnterGameOverlay,
            overlaySettings: overlaySettings,
            onOverlaySettingsChanged: onOverlaySettingsChanged,
          ),
        ),
        Expanded(child: _MonitorMain(controller: controller)),
        SizedBox(width: 322, child: _DetailsPanel(controller: controller)),
      ],
    );
  }
}

class _MediumLayout extends StatelessWidget {
  const _MediumLayout({
    required this.controller,
    required this.onEnterGameOverlay,
    required this.overlaySettings,
    required this.onOverlaySettingsChanged,
  });

  final HeartRateController controller;
  final VoidCallback onEnterGameOverlay;
  final GameOverlaySettings overlaySettings;
  final ValueChanged<GameOverlaySettings> onOverlaySettingsChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            SizedBox(
              width: 252,
              child: _Sidebar(
                controller: controller,
                onEnterGameOverlay: onEnterGameOverlay,
                overlaySettings: overlaySettings,
                onOverlaySettingsChanged: onOverlaySettingsChanged,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(
                      height: math.max(constraints.maxHeight, 670),
                      child: _MonitorMain(controller: controller),
                    ),
                    SizedBox(
                      height: 620,
                      child: _DetailsPanel(controller: controller),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CompactLayout extends StatelessWidget {
  const _CompactLayout({
    required this.controller,
    required this.onEnterGameOverlay,
    required this.overlaySettings,
    required this.onOverlaySettingsChanged,
  });

  final HeartRateController controller;
  final VoidCallback onEnterGameOverlay;
  final GameOverlaySettings overlaySettings;
  final ValueChanged<GameOverlaySettings> onOverlaySettingsChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          SizedBox(
            height: 520,
            child: _Sidebar(
              controller: controller,
              compact: true,
              onEnterGameOverlay: onEnterGameOverlay,
              overlaySettings: overlaySettings,
              onOverlaySettingsChanged: onOverlaySettingsChanged,
            ),
          ),
          SizedBox(height: 660, child: _MonitorMain(controller: controller)),
          SizedBox(height: 620, child: _DetailsPanel(controller: controller)),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.controller,
    required this.onEnterGameOverlay,
    required this.overlaySettings,
    required this.onOverlaySettingsChanged,
    this.compact = false,
  });

  final HeartRateController controller;
  final VoidCallback onEnterGameOverlay;
  final GameOverlaySettings overlaySettings;
  final ValueChanged<GameOverlaySettings> onOverlaySettingsChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final connected = controller.connectedDevice != null;
    final hasConnection =
        connected ||
        controller.status == MonitorStatus.connecting ||
        controller.status == MonitorStatus.error;
    final statusColor = _connectionColor(controller);

    return ColoredBox(
      color: AppColors.ink,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 28 : 24,
          compact ? 28 : 26,
          compact ? 28 : 24,
          22,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.coral,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.monitor_heart_outlined,
                    size: 22,
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PULSE',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      Text(
                        '实时心率',
                        style: TextStyle(
                          color: Color(0xFFA7B7B6),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 38 : 56),
            const Text(
              '设备状态',
              style: TextStyle(
                color: Color(0xFF8FA4A3),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    controller.statusLabel,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _deviceLabel(controller),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFA7B7B6),
                fontSize: 12,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 26),
            if (controller.isBusy)
              FilledButton(
                onPressed: null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      controller.status == MonitorStatus.disconnecting
                          ? '正在断开'
                          : '正在连接',
                    ),
                  ],
                ),
              )
            else
              FilledButton.icon(
                onPressed: () {
                  if (hasConnection) {
                    unawaited(controller.disconnect());
                  } else {
                    unawaited(showDeviceScanner(context, controller));
                  }
                },
                icon: Icon(
                  hasConnection ? Icons.link_off : Icons.bluetooth_searching,
                  size: 18,
                ),
                label: Text(hasConnection ? '断开连接' : '连接手环'),
              ),
            if (!hasConnection) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => unawaited(controller.toggleDemo()),
                icon: Icon(
                  controller.isDemo
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline,
                  size: 18,
                ),
                label: Text(controller.isDemo ? '结束演示' : '演示心跳'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD5DEDC),
                  side: const BorderSide(color: Color(0xFF40535A)),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: controller.hasReading && !controller.isBusy
                        ? onEnterGameOverlay
                        : null,
                    icon: const Icon(
                      Icons.picture_in_picture_alt_outlined,
                      size: 18,
                    ),
                    label: const Text('游戏角落模式'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.white,
                      disabledForegroundColor: const Color(0xFF718583),
                      side: BorderSide(
                        color: controller.hasReading
                            ? const Color(0xFF5F7779)
                            : const Color(0xFF31454C),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: () async {
                    final settings = await showGameOverlaySettingsDialog(
                      context,
                      initialSettings: overlaySettings,
                    );
                    if (settings != null) {
                      onOverlaySettingsChanged(settings);
                    }
                  },
                  tooltip: '游戏角落设置',
                  icon: const Icon(Icons.tune, size: 18),
                  style: IconButton.styleFrom(
                    foregroundColor: const Color(0xFFD5DEDC),
                    side: const BorderSide(color: Color(0xFF40535A)),
                  ),
                ),
              ],
            ),
            if (controller.errorMessage case final message?) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppColors.coral.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.coral.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFFF2C2C5),
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ),
            ],
            const Spacer(),
            const Divider(color: Color(0xFF31454C)),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  controller.bluetoothReady
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  color: controller.bluetoothReady
                      ? const Color(0xFF83BBA9)
                      : const Color(0xFF829391),
                  size: 15,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    controller.availabilityLabel,
                    style: const TextStyle(
                      color: Color(0xFF9FAFAD),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            const Text(
              'BLE Heart Rate Service · 0x180D',
              style: TextStyle(color: Color(0xFF718583), fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Color _connectionColor(HeartRateController controller) {
    if (controller.isDemo) {
      return AppColors.amber;
    }
    return switch (controller.status) {
      MonitorStatus.connected =>
        controller.readingIsStale ? AppColors.amber : const Color(0xFF66B59B),
      MonitorStatus.connecting ||
      MonitorStatus.disconnecting => AppColors.amber,
      MonitorStatus.error => AppColors.coral,
      MonitorStatus.idle => const Color(0xFF6E8584),
    };
  }

  String _deviceLabel(HeartRateController controller) {
    if (controller.isDemo) {
      return '模拟心率，用于预览动画速度';
    }
    final device = controller.connectedDevice;
    if (device != null) {
      final name = device.name?.trim();
      return name == null || name.isEmpty ? device.deviceId : name;
    }
    if (controller.status == MonitorStatus.error) {
      return '连接已结束，可重新搜索设备';
    }
    return '尚未选择蓝牙心率设备';
  }
}

class _MonitorMain extends StatelessWidget {
  const _MonitorMain({required this.controller});

  final HeartRateController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.paper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 28, 30, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '实时心率',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _monitorSubtitle(controller),
                        style: const TextStyle(
                          color: AppColors.inkMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                _StatusBadge(controller: controller),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = math.max(constraints.maxWidth - 40, 220);
                final availableHeight = math.max(
                  constraints.maxHeight - 20,
                  300,
                );
                final heartSize = math
                    .min(availableWidth * 0.62, availableHeight * 0.50)
                    .clamp(154.0, 330.0);
                return Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: EcgLine(
                          beatsPerMinute: controller.animationBpm,
                          active:
                              controller.hasReading &&
                              (!controller.readingIsStale || controller.isDemo),
                          color: controller.isDemo
                              ? AppColors.amber
                              : AppColors.coral,
                        ),
                      ),
                    ),
                    Center(
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Transform.translate(
                              offset: Offset(0, heartSize * 0.04),
                              child: HeartbeatVisualizer(
                                beatsPerMinute: controller.animationBpm,
                                active:
                                    controller.hasReading &&
                                    (!controller.readingIsStale ||
                                        controller.isDemo),
                                demo: controller.isDemo,
                                size: heartSize,
                              ),
                            ),
                            Transform.translate(
                              offset: Offset(0, -heartSize * 0.04),
                              child: _BpmReadout(controller: controller),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 0, 30, 22),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  controller.isDemo
                      ? Icons.science_outlined
                      : controller.hasReading
                      ? Icons.sensors
                      : Icons.sensors_off,
                  size: 14,
                  color: AppColors.inkMuted,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    controller.isDemo
                        ? '演示模式 · 当前读数不是真实心率'
                        : controller.hasReading
                        ? '心率广播已接入'
                        : '等待连接心率广播设备',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _monitorSubtitle(HeartRateController controller) {
    if (controller.isDemo) {
      return '使用模拟数据预览心跳动画';
    }
    final device = controller.connectedDevice;
    if (device == null) {
      return '连接手环后显示实时读数';
    }
    final name = device.name?.trim();
    return name == null || name.isEmpty ? device.deviceId : name;
  }
}

class _BpmReadout extends StatelessWidget {
  const _BpmReadout({required this.controller});

  final HeartRateController controller;

  @override
  Widget build(BuildContext context) {
    final bpm = controller.currentBpm;
    final rhythm = _rhythmLabel(controller);
    final accent = controller.isDemo
        ? AppColors.amber
        : controller.readingIsStale && bpm != null
        ? AppColors.amber
        : AppColors.coral;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.08),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Text(
                bpm?.toString() ?? '--',
                key: ValueKey<int?>(bpm),
                style: Theme.of(context).textTheme.displayLarge
                    ?.copyWith(color: AppColors.ink),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 13, left: 9),
              child: Text(
                'BPM',
                style: TextStyle(
                  color: AppColors.inkMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                rhythm,
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _readingAge(controller),
          style: TextStyle(
            color: AppColors.inkMuted.withValues(alpha: 0.82),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  String _rhythmLabel(HeartRateController controller) {
    final bpm = controller.currentBpm;
    if (bpm == null) {
      return '等待心率数据';
    }
    if (controller.readingIsStale && !controller.isDemo) {
      return '数据暂时中断';
    }
    if (bpm < 60) {
      return '心率偏慢';
    }
    if (bpm > 100) {
      return '心率偏快';
    }
    return '心率平稳';
  }

  String _readingAge(HeartRateController controller) {
    final lastReadingAt = controller.lastReadingAt;
    if (lastReadingAt == null) {
      return '尚未收到心率广播';
    }
    final seconds = DateTime.now().difference(lastReadingAt).inSeconds;
    if (seconds <= 1) {
      return '刚刚更新';
    }
    if (seconds < 60) {
      return '$seconds 秒前更新';
    }
    return '${seconds ~/ 60} 分钟前更新';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.controller});

  final HeartRateController controller;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (controller.status) {
      MonitorStatus.connected when controller.readingIsStale => (
        AppColors.amberWash,
        AppColors.amber,
      ),
      MonitorStatus.connected => (AppColors.mintWash, AppColors.mint),
      MonitorStatus.connecting ||
      MonitorStatus.disconnecting => (AppColors.amberWash, AppColors.amber),
      MonitorStatus.error => (AppColors.coralWash, AppColors.coralDark),
      MonitorStatus.idle => (AppColors.paperDeep, AppColors.inkMuted),
    };
    final badgeBackground = controller.isDemo
        ? AppColors.amberWash
        : background;
    final badgeForeground = controller.isDemo ? AppColors.amber : foreground;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: badgeBackground,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: badgeForeground,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            controller.statusLabel,
            style: TextStyle(
              color: badgeForeground,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel({required this.controller});

  final HeartRateController controller;

  @override
  Widget build(BuildContext context) {
    final samples = controller.history;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.line)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 29, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('读数详情', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text(
              '本次连接',
              style: TextStyle(color: AppColors.inkMuted, fontSize: 11),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: '最低',
                    value: controller.minimumBpm?.toString() ?? '--',
                    unit: 'BPM',
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: _Metric(
                    label: '平均',
                    value: controller.averageBpm?.toString() ?? '--',
                    unit: 'BPM',
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: _Metric(
                    label: '最高',
                    value: controller.maximumBpm?.toString() ?? '--',
                    unit: 'BPM',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const Divider(height: 1),
            _DetailRow(
              label: 'R-R 间期',
              value: controller.latestRrIntervalMs == null
                  ? '--'
                  : '${controller.latestRrIntervalMs!.round()} ms',
            ),
            _DetailRow(
              label: '皮肤接触',
              value: switch (controller.sensorContactDetected) {
                true => '已接触',
                false => '未接触',
                null => '未提供',
              },
            ),
            _DetailRow(
              label: '当前心律',
              value: _bpmRange(controller.currentBpm),
              isLast: true,
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Text('心率趋势', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(
                  '${samples.length} 次读数',
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            HeartRateChart(samples: samples),
            const SizedBox(height: 10),
            const Row(
              children: [
                Text(
                  '较早',
                  style: TextStyle(color: AppColors.inkMuted, fontSize: 10),
                ),
                Spacer(),
                Text(
                  '现在',
                  style: TextStyle(color: AppColors.inkMuted, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 25),
            const Divider(height: 1),
            const SizedBox(height: 20),
            Text('数据源', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 13),
            _SourceRow(
              icon: controller.isDemo
                  ? Icons.science_outlined
                  : Icons.bluetooth_connected,
              label: controller.isDemo ? '模拟心率' : _sourceName(controller),
            ),
            const SizedBox(height: 9),
            _SourceRow(
              icon: Icons.memory,
              label: controller.isDemo ? '演示数据' : '标准 BLE Heart Rate',
            ),
            const SizedBox(height: 9),
            _SourceRow(
              icon: Icons.schedule,
              label: _lastUpdateLabel(controller),
            ),
          ],
        ),
      ),
    );
  }

  String _bpmRange(int? bpm) {
    if (bpm == null) {
      return '--';
    }
    if (bpm < 60) {
      return '偏慢';
    }
    if (bpm > 100) {
      return '偏快';
    }
    return '平稳';
  }

  String _sourceName(HeartRateController controller) {
    final device = controller.connectedDevice;
    if (device == null) {
      return '未连接';
    }
    final name = device.name?.trim();
    return name == null || name.isEmpty ? device.deviceId : name;
  }

  String _lastUpdateLabel(HeartRateController controller) {
    final lastReadingAt = controller.lastReadingAt;
    if (lastReadingAt == null) {
      return '尚未更新';
    }
    final seconds = DateTime.now().difference(lastReadingAt).inSeconds;
    if (seconds <= 1) {
      return '刚刚更新';
    }
    if (seconds < 60) {
      return '$seconds 秒前更新';
    }
    return '${seconds ~/ 60} 分钟前更新';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.unit});

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.inkMuted, fontSize: 10),
        ),
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 26,
                    height: 1,
                    fontWeight: FontWeight.w500,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 3),
            Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Text(
                unit,
                style: const TextStyle(
                  color: AppColors.inkMuted,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 12),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.inkMuted),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.inkMuted,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
