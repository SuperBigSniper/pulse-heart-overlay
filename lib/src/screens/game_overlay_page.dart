import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../heart_rate/heart_rate_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/heartbeat_visualizer.dart';

enum OverlayResizeCorner { topLeft, topRight, bottomLeft, bottomRight }

class GameOverlayPage extends StatelessWidget {
  const GameOverlayPage({
    super.key,
    required this.controller,
    required this.onRestore,
    required this.onStartDragging,
    required this.onResizeStart,
    required this.onResize,
    required this.onScale,
  });

  static const windowSize = Size(220, 220);
  static const minimumWindowSize = Size(140, 140);
  static const maximumWindowSize = Size(480, 480);

  final HeartRateController controller;
  final VoidCallback onRestore;
  final VoidCallback onStartDragging;
  final ValueChanged<OverlayResizeCorner> onResizeStart;
  final void Function(OverlayResizeCorner corner, Offset delta) onResize;
  final ValueChanged<double> onScale;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final bpm = controller.currentBpm;
        final active =
            controller.hasReading &&
            (!controller.readingIsStale || controller.isDemo);

        return Material(
          color: Colors.transparent,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): onRestore,
            },
            child: Focus(
              autofocus: true,
              child: Semantics(
                label: bpm == null ? '等待心率数据' : '当前心率 $bpm 次每分钟',
                hint: '双击恢复完整界面，拖动四角缩放',
                child: Listener(
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent) {
                      onScale(-event.scrollDelta.dy * 0.25);
                    }
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onDoubleTap: onRestore,
                          onPanStart: (_) => onStartDragging(),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.move,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final size = math.min(
                                  constraints.maxWidth,
                                  constraints.maxHeight,
                                );
                                return _OverlayHeartRateView(
                                  controller: controller,
                                  active: active,
                                  size: size,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      for (final corner in OverlayResizeCorner.values)
                        _OverlayResizeHandle(
                          corner: corner,
                          onStart: () => onResizeStart(corner),
                          onUpdate: (delta) => onResize(corner, delta),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Rect resizedOverlayBounds({
  required Rect startBounds,
  required OverlayResizeCorner corner,
  required Offset totalDelta,
}) {
  final signedDelta =
      (totalDelta.dx * corner.horizontalSign +
          totalDelta.dy * corner.verticalSign) /
      2;
  final size = (startBounds.shortestSide + signedDelta).clamp(
    GameOverlayPage.minimumWindowSize.width,
    GameOverlayPage.maximumWindowSize.width,
  );

  return switch (corner) {
    OverlayResizeCorner.topLeft => Rect.fromLTWH(
      startBounds.right - size,
      startBounds.bottom - size,
      size,
      size,
    ),
    OverlayResizeCorner.topRight => Rect.fromLTWH(
      startBounds.left,
      startBounds.bottom - size,
      size,
      size,
    ),
    OverlayResizeCorner.bottomLeft => Rect.fromLTWH(
      startBounds.right - size,
      startBounds.top,
      size,
      size,
    ),
    OverlayResizeCorner.bottomRight => Rect.fromLTWH(
      startBounds.left,
      startBounds.top,
      size,
      size,
    ),
  };
}

extension on OverlayResizeCorner {
  double get horizontalSign => switch (this) {
    OverlayResizeCorner.topLeft || OverlayResizeCorner.bottomLeft => -1,
    OverlayResizeCorner.topRight || OverlayResizeCorner.bottomRight => 1,
  };

  double get verticalSign => switch (this) {
    OverlayResizeCorner.topLeft || OverlayResizeCorner.topRight => -1,
    OverlayResizeCorner.bottomLeft || OverlayResizeCorner.bottomRight => 1,
  };

  Alignment get alignment => switch (this) {
    OverlayResizeCorner.topLeft => Alignment.topLeft,
    OverlayResizeCorner.topRight => Alignment.topRight,
    OverlayResizeCorner.bottomLeft => Alignment.bottomLeft,
    OverlayResizeCorner.bottomRight => Alignment.bottomRight,
  };

  MouseCursor get cursor => switch (this) {
    OverlayResizeCorner.topLeft ||
    OverlayResizeCorner.bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
    OverlayResizeCorner.topRight ||
    OverlayResizeCorner.bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
  };
}

class _OverlayHeartRateView extends StatelessWidget {
  const _OverlayHeartRateView({
    required this.controller,
    required this.active,
    required this.size,
  });

  final HeartRateController controller;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bpm = controller.currentBpm;
    final isStale = controller.readingIsStale && !controller.isDemo;
    final heartSize = size * 0.84;
    final numberSize = size * 0.24;
    final unitSize = math.max(9.0, size * 0.052);
    final shadow = Shadow(
      color: AppColors.ink.withValues(alpha: 0.92),
      blurRadius: math.max(6, size * 0.045),
      offset: const Offset(0, 1),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: EcgLine(
              beatsPerMinute: controller.animationBpm,
              active: active,
              color: controller.isDemo ? AppColors.amber : AppColors.coral,
            ),
          ),
        ),
        Center(
          child: HeartbeatVisualizer(
            beatsPerMinute: controller.animationBpm,
            active: active,
            demo: controller.isDemo,
            size: heartSize,
            showGuides: false,
            showShadow: false,
          ),
        ),
        Align(
          alignment: const Alignment(0, 0.68),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Text(
                  bpm?.toString() ?? '--',
                  key: ValueKey<int?>(bpm),
                  maxLines: 1,
                  style: TextStyle(
                    color: isStale
                        ? AppColors.white.withValues(alpha: 0.62)
                        : AppColors.white,
                    fontSize: numberSize,
                    height: 0.9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    shadows: [shadow],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  left: math.max(4, size * 0.025),
                  bottom: math.max(2, size * 0.018),
                ),
                child: Text(
                  'BPM',
                  style: TextStyle(
                    color: isStale
                        ? AppColors.white.withValues(alpha: 0.48)
                        : const Color(0xFFD8E2E0),
                    fontSize: unitSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                    shadows: [shadow],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OverlayResizeHandle extends StatefulWidget {
  const _OverlayResizeHandle({
    required this.corner,
    required this.onStart,
    required this.onUpdate,
  });

  final OverlayResizeCorner corner;
  final VoidCallback onStart;
  final ValueChanged<Offset> onUpdate;

  @override
  State<_OverlayResizeHandle> createState() => _OverlayResizeHandleState();
}

class _OverlayResizeHandleState extends State<_OverlayResizeHandle> {
  Offset? _startPosition;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.corner.alignment,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          _startPosition = details.globalPosition;
          widget.onStart();
        },
        onPanUpdate: (details) {
          final startPosition = _startPosition;
          if (startPosition != null) {
            widget.onUpdate(details.globalPosition - startPosition);
          }
        },
        onPanEnd: (_) => _startPosition = null,
        onPanCancel: () => _startPosition = null,
        child: MouseRegion(
          cursor: widget.corner.cursor,
          child: const SizedBox.square(dimension: 26),
        ),
      ),
    );
  }
}
