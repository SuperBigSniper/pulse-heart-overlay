import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heartbeat_monitor/src/heart_rate/heart_rate_controller.dart';
import 'package:heartbeat_monitor/src/screens/game_overlay_page.dart';

void main() {
  testWidgets('game overlay shows only the live heart rate', (tester) async {
    final controller = HeartRateController();
    await controller.toggleDemo();
    var restoreCount = 0;

    await tester.binding.setSurfaceSize(GameOverlayPage.windowSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: GameOverlayPage(
          controller: controller,
          onRestore: () => restoreCount++,
          onStartDragging: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('84'), findsOneWidget);
    expect(find.text('BPM'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
    expect(find.text('实时心率'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(restoreCount, 1);

    await controller.toggleDemo();
    controller.dispose();
  });
}
