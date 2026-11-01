import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../heart_rate/heart_rate_controller.dart';
import '../theme/app_theme.dart';

class GameOverlayPage extends StatelessWidget {
  const GameOverlayPage({
    super.key,
    required this.controller,
    required this.onRestore,
    required this.onStartDragging,
  });

  static const windowSize = Size(168, 72);

  final HeartRateController controller;
  final VoidCallback onRestore;
  final VoidCallback onStartDragging;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final bpm = controller.currentBpm;
        final isStale = controller.readingIsStale && !controller.isDemo;

        return Material(
          color: AppColors.ink,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): onRestore,
            },
            child: Focus(
              autofocus: true,
              child: Semantics(
                label: bpm == null ? '等待心率数据' : '当前心率 $bpm 次每分钟',
                hint: '双击恢复完整界面',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: onRestore,
                  onPanStart: (_) => onStartDragging(),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.move,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: FittedBox(
                                key: ValueKey<int?>(bpm),
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  bpm?.toString() ?? '--',
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: isStale
                                        ? AppColors.white.withValues(
                                            alpha: 0.58,
                                          )
                                        : AppColors.white,
                                    fontSize: 42,
                                    height: 0.95,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'BPM',
                            style: TextStyle(
                              color: isStale
                                  ? AppColors.white.withValues(alpha: 0.45)
                                  : const Color(0xFFAFC0BE),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
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
