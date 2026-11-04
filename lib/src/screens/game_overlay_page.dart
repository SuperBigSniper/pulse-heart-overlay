import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../heart_rate/heart_rate_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/heartbeat_visualizer.dart';
import 'game_overlay_settings.dart';

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
    required this.settings,
  });

  static const windowSize = Size(90, 120);
  static const minimumWindowSize = Size(10, 10);

  final HeartRateController controller;
  final VoidCallback onRestore;
  final VoidCallback onStartDragging;
  final ValueChanged<OverlayResizeCorner> onResizeStart;
  final void Function(OverlayResizeCorner corner, Offset delta) onResize;
  final ValueChanged<double> onScale;
  final GameOverlaySettings settings;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): onRestore},
        child: Focus(
          autofocus: true,
          child: Semantics(
            label: '游戏角落模式',
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
                            return AnimatedBuilder(
                              animation: Listenable.merge([
                                controller.readingChanges,
                                controller.connectionChanges,
                              ]),
                              builder: (context, child) {
                                final active =
                                    controller.hasReading &&
                                    (!controller.readingIsStale ||
                                        controller.isDemo);
                                return _OverlayHeartRateView(
                                  controller: controller,
                                  active: active,
                                  size: size,
                                  canvasSize: Size(
                                    constraints.maxWidth,
                                    constraints.maxHeight,
                                  ),
                                  settings: settings,
                                );
                              },
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
  }
}

Rect resizedOverlayBounds({
  required Rect startBounds,
  required OverlayResizeCorner corner,
  required Offset totalDelta,
  required Size maximumSize,
}) {
  final width = (startBounds.width + totalDelta.dx * corner.horizontalSign)
      .clamp(GameOverlayPage.minimumWindowSize.width, maximumSize.width)
      .toDouble();
  final height = (startBounds.height + totalDelta.dy * corner.verticalSign)
      .clamp(GameOverlayPage.minimumWindowSize.height, maximumSize.height)
      .toDouble();

  return switch (corner) {
    OverlayResizeCorner.topLeft => Rect.fromLTWH(
      startBounds.right - width,
      startBounds.bottom - height,
      width,
      height,
    ),
    OverlayResizeCorner.topRight => Rect.fromLTWH(
      startBounds.left,
      startBounds.bottom - height,
      width,
      height,
    ),
    OverlayResizeCorner.bottomLeft => Rect.fromLTWH(
      startBounds.right - width,
      startBounds.top,
      width,
      height,
    ),
    OverlayResizeCorner.bottomRight => Rect.fromLTWH(
      startBounds.left,
      startBounds.top,
      width,
      height,
    ),
  };
}

Size overlayMaximumSizeFor(BuildContext context) {
  final view = View.of(context);
  final displaySize = view.display.size / view.devicePixelRatio;
  return Size(
    math.max(GameOverlayPage.minimumWindowSize.width, displaySize.width),
    math.max(GameOverlayPage.minimumWindowSize.height, displaySize.height),
  );
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
    required this.canvasSize,
    required this.settings,
  });

  final HeartRateController controller;
  final bool active;
  final double size;
  final Size canvasSize;
  final GameOverlaySettings settings;

  @override
  Widget build(BuildContext context) {
    final bpm = controller.currentBpm;
    final isStale = controller.readingIsStale && !controller.isDemo;
    final heartSize = size * 0.61 * settings.animationScale;
    final numberSize = size * 0.2 * settings.textScale;
    final unitSize = math.max(9.0, size * 0.042 * settings.textScale);
    final gap = math.max(1, size * 0.012).toDouble();
    final contentHeight = heartSize + gap + numberSize * 0.9 + unitSize;
    final ecgAlignment = canvasSize.height == 0
        ? 0.5
        : (((canvasSize.height - contentHeight) / 2 + heartSize * 0.51) /
                  canvasSize.height)
              .clamp(0.15, 0.85)
              .toDouble();
    // 浮层文字只保留一层柔和下投影保证可读性，不再用四方向描边，
    // 避免在浅色游戏画面上看起来像文字带了一圈边框。
    final textShadows = _overlayTextShadows(numberSize);

    return HeartbeatMotion(
      beatsPerMinute: bpm,
      active: active,
      speedScale: settings.animationSpeed,
      builder: (context, animation) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: EcgLine(
                  animation: animation,
                  beatsPerMinute: bpm,
                  active: active,
                  color: controller.isDemo ? AppColors.amber : AppColors.coral,
                  verticalAlignment: ecgAlignment,
                ),
              ),
            ),
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HeartbeatVisualizer(
                      animation: animation,
                      beatsPerMinute: bpm,
                      active: active,
                      demo: controller.isDemo,
                      size: heartSize,
                      showGuides: false,
                      showShadow: false,
                    ),
                    SizedBox(height: gap),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Text(
                        bpm?.toString() ?? '--',
                        key: ValueKey<int?>(bpm),
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isStale
                              ? AppColors.white.withValues(alpha: 0.62)
                              : AppColors.white,
                          fontSize: numberSize,
                          height: 0.9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          shadows: textShadows,
                        ),
                      ),
                    ),
                    Text(
                      'BPM',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isStale
                            ? AppColors.white.withValues(alpha: 0.48)
                            : const Color(0xFFD8E2E0),
                        fontSize: unitSize,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                        shadows: _overlayTextShadows(unitSize),
                      ),
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

/// 游戏浮层文字不再加任何阴影：描边和模糊阴影都会在字形周围形成
/// 可见的"边框/光晕"，浅色画面上尤其明显。
List<Shadow> _overlayTextShadows(double fontSize) => const [];

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
