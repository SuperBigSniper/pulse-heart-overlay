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
          settings: const GameOverlaySettings(animationSpeed: 1.4),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('84'), findsOneWidget);
    expect(find.text('BPM'), findsOneWidget);
    expect(find.byType(HeartbeatVisualizer), findsOneWidget);
    final initialVisualizer = tester.widget<HeartbeatVisualizer>(
      find.byType(HeartbeatVisualizer),
    );
    final ecgLine = tester.widget<EcgLine>(find.byType(EcgLine));
    expect(initialVisualizer.showGuides, isFalse);
    expect(initialVisualizer.showShadow, isFalse);
    expect(ecgLine.animation, same(initialVisualizer.animation));
    expect(ecgLine.beatsPerMinute, controller.currentBpm);
    expect(
      tester.widget<HeartbeatMotion>(find.byType(HeartbeatMotion)).speedScale,
      1.4,
    );
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

    await tester.pump(const Duration(milliseconds: 900));
    final updatedVisualizer = tester.widget<HeartbeatVisualizer>(
      find.byType(HeartbeatVisualizer),
    );
    expect(updatedVisualizer.beatsPerMinute, controller.currentBpm);
    expect(find.text('${controller.currentBpm}'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(restoreCount, 1);

    await controller.toggleDemo();
    controller.dispose();
  });

  test('corner resizing adjusts width and height independently', () {
    const start = Rect.fromLTWH(100, 80, 220, 220);

    final bottomRight = resizedOverlayBounds(
      startBounds: start,
      corner: OverlayResizeCorner.bottomRight,
      totalDelta: const Offset(60, 40),
      maximumSize: const Size(720, 520),
    );
    expect(bottomRight, const Rect.fromLTWH(100, 80, 280, 260));

    final topLeft = resizedOverlayBounds(
      startBounds: start,
      corner: OverlayResizeCorner.topLeft,
      totalDelta: const Offset(-60, -40),
      maximumSize: const Size(720, 520),
    );
    expect(topLeft, const Rect.fromLTWH(40, 40, 280, 260));

    final minimum = resizedOverlayBounds(
      startBounds: start,
      corner: OverlayResizeCorner.bottomRight,
      totalDelta: const Offset(-500, -500),
      maximumSize: const Size(720, 520),
    );
    expect(minimum.size, GameOverlayPage.minimumWindowSize);

    final maximum = resizedOverlayBounds(
      startBounds: start,
      corner: OverlayResizeCorner.bottomRight,
      totalDelta: const Offset(1000, 1000),
      maximumSize: const Size(720, 520),
    );
    expect(maximum.size, const Size(720, 520));
  });

  testWidgets('game overlay renders with a custom aspect ratio', (
    tester,
  ) async {
    final controller = HeartRateController();
    await controller.toggleDemo();
    const overlaySize = Size(360, 180);

    await tester.binding.setSurfaceSize(overlaySize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: GameOverlayPage(
          controller: controller,
          onRestore: () {},
          onStartDragging: () {},
          onResizeStart: (_) {},
          onResize: (_, _) {},
          onScale: (_) {},
          settings: GameOverlaySettings(
            overlayWidth: overlaySize.width,
            overlayHeight: overlaySize.height,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      tester.getCenter(find.text('84')).dx,
      closeTo(tester.getCenter(find.byType(HeartbeatVisualizer)).dx, 0.01),
    );
    await controller.toggleDemo();
    controller.dispose();
  });
}
