import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heartbeat_monitor/src/screens/game_overlay_settings.dart';
import 'package:heartbeat_monitor/src/widgets/game_overlay_settings_dialog.dart';

void main() {
  testWidgets('game overlay settings can be saved', (tester) async {
    GameOverlaySettings? savedSettings;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                savedSettings = await showGameOverlaySettingsDialog(
                  context,
                  initialSettings: GameOverlaySettings.defaults,
                );
              },
              child: const Text('打开设置'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('打开设置'));
    await tester.pumpAndSettle();

    expect(find.text('动画大小'), findsOneWidget);
    expect(find.text('心率文字大小'), findsOneWidget);
    expect(find.text('动画节奏'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(3));

    await tester.drag(find.byType(Slider).first, const Offset(-500, 0));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(savedSettings, isNotNull);
    expect(
      savedSettings!.animationScale,
      lessThan(GameOverlaySettings.defaults.animationScale),
    );
  });
}
