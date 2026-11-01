import 'package:flutter/material.dart';

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
          return AlertDialog(
            title: const Text('游戏角落设置'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SettingSlider(
                    label: '动画大小',
                    value: draft.animationScale,
                    minimum: 0.6,
                    maximum: 1.3,
                    divisions: 14,
                    valueLabel: '${(draft.animationScale * 100).round()}%',
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
                    minimum: 0.7,
                    maximum: 1.5,
                    divisions: 16,
                    valueLabel: '${(draft.textScale * 100).round()}%',
                    onChanged: (value) {
                      setDialogState(() {
                        draft = draft.copyWith(textScale: value);
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  _SettingSlider(
                    label: '动画节奏',
                    description: '100% 对应实时 BPM，数值越低动画越慢',
                    value: draft.animationSpeed,
                    minimum: 0.5,
                    maximum: 1.2,
                    divisions: 14,
                    valueLabel: '${(draft.animationSpeed * 100).round()}%',
                    onChanged: (value) {
                      setDialogState(() {
                        draft = draft.copyWith(animationSpeed: value);
                      });
                    },
                  ),
                ],
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
    this.description,
  });

  final String label;
  final String? description;
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
        if (description case final description?) ...[
          const SizedBox(height: 2),
          Text(
            description,
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 11),
          ),
        ],
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
