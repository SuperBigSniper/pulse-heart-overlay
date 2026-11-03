import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heartbeat_monitor/src/heart_rate/heart_rate_controller.dart';
import 'package:heartbeat_monitor/src/heart_rate/heartbeat_timing.dart';
import 'package:heartbeat_monitor/src/widgets/heartbeat_visualizer.dart';

void main() {
  test('visual heartbeat rate follows the measured BPM', () {
    const anchors = <int, double>{
      50: 50 / 60,
      60: 1,
      75: 1.25,
      90: 1.5,
      100: 100 / 60,
      120: 2,
    };

    for (final anchor in anchors.entries) {
      expect(visualHeartbeatRateFor(anchor.key), closeTo(anchor.value, 1e-6));
      expect(
        heartbeatPeriodFor(anchor.key).inMilliseconds,
        (1000 / anchor.value).round(),
      );
    }
  });

  test('visual heartbeat rate changes continuously between tested values', () {
    expect(visualHeartbeatRateFor(68), closeTo(68 / 60, 0.0000001));
    expect(visualHeartbeatRateFor(82), closeTo(82 / 60, 0.0000001));
    expect(heartbeatPeriodFor(68).inMilliseconds, 882);
    expect(heartbeatPeriodFor(105).inMilliseconds, 571);
    expect(heartbeatPeriodFor(115).inMilliseconds, 522);
  });

  test('user speed scale changes the tempo without changing the BPM', () {
    expect(
      visualHeartbeatRateFor(90, speedScale: 1.5),
      closeTo(2.25, 0.0000001),
    );
    expect(heartbeatPeriodFor(90, speedScale: 2).inMilliseconds, 333);
    expect(heartbeatPeriodFor(90, speedScale: 0.5).inMilliseconds, 1333);
    expect(
      heartbeatPeriodFor(90, speedScale: 20),
      heartbeatPeriodFor(90, speedScale: maximumHeartbeatSpeedScale),
    );
  });

  test('visual heartbeat rate stays within the supported sensor range', () {
    expect(visualHeartbeatRateFor(10), 0.5);
    expect(visualHeartbeatRateFor(250), closeTo(220 / 60, 0.0000001));
  });

  test('heartbeat contraction strength follows emotional intensity', () {
    final calm = heartbeatStrengthFor(50);
    final elevated = heartbeatStrengthFor(100);
    final intense = heartbeatStrengthFor(150);

    expect(calm, lessThan(elevated));
    expect(elevated, lessThan(intense));
    expect(intense - calm, greaterThan(0.05));
  });

  test('ECG waveform scrolls from left to right with the heartbeat', () {
    final laterCycle = ecgCycleFor(0.5, 0.2);
    final earlierCycle = ecgCycleFor(0.5, 0.1);

    expect(laterCycle, lessThan(earlierCycle));
    expect(ecgCycleFor(0.505, 0), closeTo(0.235, 0.001));
  });

  test('heartbeat impulse returns to rest during a cycle', () {
    expect(heartbeatImpulse(0.0), lessThan(0.06));
    expect(heartbeatImpulse(0.08), greaterThan(0.9));
    expect(heartbeatImpulse(0.255), lessThan(0.1));
    expect(heartbeatImpulse(0.70), lessThan(0.01));
  });

  testWidgets('visualizer renders and animates without a Bluetooth device', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: HeartbeatVisualizer(
              beatsPerMinute: 92,
              active: true,
              size: 240,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(HeartbeatVisualizer), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
  });

  testWidgets('running animation adopts a new BPM period immediately', (
    tester,
  ) async {
    final bpm = ValueNotifier<int>(60);
    Animation<double>? animation;

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<int>(
          valueListenable: bpm,
          builder: (context, value, child) {
            return HeartbeatMotion(
              beatsPerMinute: value,
              active: true,
              builder: (context, value) {
                animation = value;
                return const SizedBox.shrink();
              },
            );
          },
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 250));
    final slowProgress = animation!.value;
    expect(slowProgress, closeTo(0.25, 0.02));

    bpm.value = 100;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final fastProgress = animation!.value - slowProgress;

    expect(fastProgress, closeTo(250 / 600, 0.02));
    expect(fastProgress, greaterThan(slowProgress));

    bpm.dispose();
  });

  testWidgets('live readings do not notify connection and history widgets', (
    tester,
  ) async {
    final controller = HeartRateController();
    await controller.toggleDemo();
    final connectionRevision = controller.connectionChanges.value;
    final readingRevision = controller.readingChanges.value;
    final historyRevision = controller.savedHistoryChanges.value;

    await tester.pump(const Duration(seconds: 2));

    expect(controller.connectionChanges.value, connectionRevision);
    expect(controller.readingChanges.value, greaterThan(readingRevision));
    expect(controller.savedHistoryChanges.value, historyRevision);

    controller.pauseLiveUiNotifications();
    final pausedReadingRevision = controller.readingChanges.value;
    await tester.pump(const Duration(seconds: 2));
    expect(controller.readingChanges.value, pausedReadingRevision);
    controller.resumeLiveUiNotifications();
    await tester.pump();
    expect(controller.readingChanges.value, greaterThan(pausedReadingRevision));

    await controller.toggleDemo();
    controller.dispose();
  });
}
