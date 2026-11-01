import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heartbeat_monitor/src/heart_rate/heartbeat_timing.dart';
import 'package:heartbeat_monitor/src/widgets/heartbeat_visualizer.dart';

void main() {
  test('heartbeat period follows BPM', () {
    final slow = heartbeatPeriodFor(50);
    final resting = heartbeatPeriodFor(75);
    final fast = heartbeatPeriodFor(150);

    expect(slow.inMilliseconds, 1200);
    expect(resting.inMilliseconds, 800);
    expect(fast.inMilliseconds, 400);
    expect(slow, greaterThan(resting));
    expect(resting, greaterThan(fast));
  });

  test(
    'animation speed scale changes the pulse period without changing BPM',
    () {
      final normal = heartbeatPeriodFor(75);
      final slower = heartbeatPeriodFor(75, speedScale: 1.5);

      expect(slower.inMilliseconds, 1200);
      expect(slower, greaterThan(normal));
    },
  );

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
}
