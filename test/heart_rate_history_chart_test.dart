import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heartbeat_monitor/src/heart_rate/heart_rate_history.dart';
import 'package:heartbeat_monitor/src/theme/app_theme.dart';
import 'package:heartbeat_monitor/src/widgets/heart_rate_history_chart.dart';

void main() {
  testWidgets('paints an empty display list without throwing', (tester) async {
    final start = DateTime(2026, 11, 3, 10);
    final points = List<HeartRateHistoryPoint>.generate(3, (index) {
      return HeartRateHistoryPoint(
        id: '$index',
        beatsPerMinute: 70 + index * 10,
        recordedAt: start.add(Duration(minutes: index * 10)),
        source: 'Band A',
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 700,
              child: HeartRateHistoryChart(
                points: points,
                // Downsampling can legitimately produce an empty display list
                // while the full list is not empty.
                displayPoints: const <HeartRateHistoryPoint>[],
                selectedPointId: null,
                onPointSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(HeartRateHistoryChart.chartKey), findsOneWidget);
  });
}
