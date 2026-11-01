import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../screens/game_overlay_page.dart';
import '../screens/game_overlay_settings.dart';
import '../theme/app_theme.dart';

Future<GameOverlaySettings?> showGameOverlaySettingsDialog(
  BuildContext context, {
  required GameOverlaySettings initialSettings,
}) {
  var draft = initialSettings;

  return showDialog<GameOverlaySettings>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final maximumSize = overlayMaximumSizeFor(context);
          final minimumSize = GameOverlayPage.minimumWindowSize;
          final overlayWidth = draft.overlayWidth
              .clamp(minimumSize.width, maximumSize.width)
              .toDouble();
          final overlayHeight = draft.overlayHeight
              .clamp(minimumSize.height, maximumSize.height)
              .toDouble();
          draft = draft.copyWith(
            overlayWidth: overlayWidth,
            overlayHeight: overlayHeight,
          );

          return AlertDialog(
            title: const Text('游戏角落设置'),
            content: SizedBox(
              width: 460,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.68,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SettingSlider(
                        label: '动画大小',
                        value: draft.animationScale,
                        minimum: 0.4,
                        maximum: 2.0,
                        divisions: 16,
                        valueLabel:
                            '${draft.animationScale.toStringAsFixed(1)}×',
                        onChanged: (value) {
                          setDialogState(() {
                            draft = draft.copyWith(animationScale: value);
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      _SettingSlider(
                        label: '心率文字大小',
                        value: draft.textScale,
                        minimum: 0.5,
                        maximum: 2.2,
                        divisions: 17,
                        valueLabel: '${draft.textScale.toStringAsFixed(1)}×',
                        onChanged: (value) {
                          setDialogState(() {
                            draft = draft.copyWith(textScale: value);
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      _SettingSlider(
                        label: '心跳速度',
                        value: draft.animationSpeed,
                        minimum: 0.5,
                        maximum: 2.0,
                        divisions: 15,
                        valueLabel:
                            '${draft.animationSpeed.toStringAsFixed(1)}×',
                        onChanged: (value) {
                          setDialogState(() {
                            draft = draft.copyWith(animationSpeed: value);
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '角落窗口',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _SettingSlider(
                        label: '宽度',
                        value: overlayWidth,
                        minimum: minimumSize.width,
                        maximum: maximumSize.width,
                        divisions: math.max(
                          1,
                          (maximumSize.width - minimumSize.width).round(),
                        ),
                        valueLabel: '${draft.overlayWidth.round()} px',
                        onChanged: (value) {
                          setDialogState(() {
                            draft = draft.copyWith(overlayWidth: value);
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      _SettingSlider(
                        label: '高度',
                        value: overlayHeight,
                        minimum: minimumSize.height,
                        maximum: maximumSize.height,
                        divisions: math.max(
                          1,
                          (maximumSize.height - minimumSize.height).round(),
                        ),
                        valueLabel: '${draft.overlayHeight.round()} px',
                        onChanged: (value) {
                          setDialogState(() {
                            draft = draft.copyWith(overlayHeight: value);
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setDialogState(() {
                    draft = GameOverlaySettings.defaults;
                  });
                },
                child: const Text('恢复默认'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(draft),
                child: const Text('保存'),
              ),
            ],
          );
        },
      );
    },
  );
}

class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.label,
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double minimum;
  final double maximum;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              valueLabel,
              style: const TextStyle(
                color: AppColors.inkMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: minimum,
          max: maximum,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
