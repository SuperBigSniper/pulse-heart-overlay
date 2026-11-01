import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heartbeat_monitor/src/heart_rate/heart_rate_controller.dart';
import 'package:heartbeat_monitor/src/screens/game_overlay_page.dart';
import 'package:heartbeat_monitor/src/screens/game_overlay_settings.dart';
import 'package:heartbeat_monitor/src/widgets/heartbeat_visualizer.dart';

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
          onResizeStart: (_) {},
          onResize: (_, _) {},
          onScale: (_) {},
          settings: GameOverlaySettings.defaults,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('84'), findsOneWidget);
    expect(find.text('BPM'), findsOneWidget);
    expect(find.byType(HeartbeatVisualizer), findsOneWidget);
    final visualizer = tester.widget<HeartbeatVisualizer>(
      find.byType(HeartbeatVisualizer),
    );
    expect(visualizer.showGuides, isFalse);
    expect(visualizer.showShadow, isFalse);
    expect(find.byType(Icon), findsNothing);
    expect(find.text('实时心率'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Material && widget.color == Colors.transparent,
      ),
      findsOneWidget,
    );
    expect(
      tester.getCenter(find.text('84')).dx,
      closeTo(tester.getCenter(find.byType(HeartbeatVisualizer)).dx, 0.01),
    );
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(restoreCount, 1);

    await controller.toggleDemo();
    controller.dispose();
  });

  test(
    'corner resizing keeps a square overlay and anchors the opposite side',
    () {
      const start = Rect.fromLTWH(100, 80, 220, 220);

      final bottomRight = resizedOverlayBounds(
        startBounds: start,
        corner: OverlayResizeCorner.bottomRight,
        totalDelta: const Offset(60, 60),
      );
      expect(bottomRight, const Rect.fromLTWH(100, 80, 280, 280));

      final topLeft = resizedOverlayBounds(
        startBounds: start,
        corner: OverlayResizeCorner.topLeft,
        totalDelta: const Offset(-60, -60),
      );
      expect(topLeft, const Rect.fromLTWH(40, 20, 280, 280));

      final minimum = resizedOverlayBounds(
        startBounds: start,
        corner: OverlayResizeCorner.bottomRight,
        totalDelta: const Offset(-500, -500),
      );
      expect(minimum.size, GameOverlayPage.minimumWindowSize);
    },
  );
}
