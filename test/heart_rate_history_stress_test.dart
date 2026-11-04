import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heartbeat_monitor/src/heart_rate/heart_rate_controller.dart';
import 'package:heartbeat_monitor/src/heart_rate/heart_rate_history.dart';
import 'package:heartbeat_monitor/src/screens/heart_rate_history_page.dart';
import 'package:heartbeat_monitor/src/theme/app_theme.dart';
import 'package:heartbeat_monitor/src/widgets/heart_rate_history_chart.dart';

import 'file_cleanup.dart';

void main() {
  test(
    'loads and caps a 120k-point history within the stress budget',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pulse-history-stress-',
      );
      addTearDown(() => deleteDirectoryWithRetry(directory));
      final pointsFile = File(
        '${directory.path}${Platform.pathSeparator}'
        'pulse_heart_rate_points.ndjson',
      );
      final buffer = StringBuffer();
      final start = DateTime.now().subtract(const Duration(hours: 36));
      for (var index = 0; index < 120000; index++) {
        final recordedAt = start.add(Duration(seconds: index));
        buffer.writeln(
          jsonEncode(<String, Object>{
            'id': recordedAt.microsecondsSinceEpoch.toString(),
            'bpm': 60 + index % 70,
            'recordedAt': recordedAt.toUtc().toIso8601String(),
            'source': 'Stress Band',
          }),
        );
      }
      await pointsFile.writeAsString(buffer.toString(), flush: true);

      final store = HeartRateHistoryStore(
        directoryProvider: () async => directory,
        saveDelay: const Duration(days: 1),
        maxPoints: 100000,
      );
      final stopwatch = Stopwatch()..start();
      await store.load();
      stopwatch.stop();

      expect(store.points, hasLength(100000));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 15)));
      store.dispose();
    },
  );

  test('sustained inserts at the cap stay bounded', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pulse-history-stress-',
    );
    addTearDown(() => deleteDirectoryWithRetry(directory));
    final store = HeartRateHistoryStore(
      directoryProvider: () async => directory,
      saveDelay: const Duration(days: 1),
      maxPendingPoints: 100000,
      maxPoints: 10000,
    );
    await store.load();
    final start = DateTime.now().subtract(const Duration(seconds: 40000));
    final stopwatch = Stopwatch()..start();
    HeartRateHistoryPoint? lastPoint;
    for (var index = 0; index < 40000; index++) {
      lastPoint = store.addMeasurement(
        beatsPerMinute: 70 + index % 40,
        recordedAt: start.add(Duration(seconds: index)),
        source: 'Stress Band',
      );
    }
    stopwatch.stop();

    expect(store.points.length, lessThanOrEqualTo(10000));
    expect(store.points.length, greaterThan(9000));
    expect(store.points.last.id, lastPoint!.id);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
    store.dispose();
  });

  testWidgets('rapid range changes keep one latest snapshot request', (
    tester,
  ) async {
    late Directory directory;
    late HeartRateHistoryStore store;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp(
        'pulse-history-page-stress-',
      );
      store = HeartRateHistoryStore(
        directoryProvider: () async => directory,
        saveDelay: const Duration(days: 1),
        maxPendingPoints: 100000,
      );
      await store.load();
      final start = DateTime.now().subtract(const Duration(hours: 7));
      for (var index = 0; index < 25000; index++) {
        store.addMeasurement(
          beatsPerMinute: 65 + index % 50,
          recordedAt: start.add(Duration(seconds: index)),
          source: 'Stress Band',
        );
      }
    });
    addTearDown(() => deleteDirectoryWithRetry(directory));
    final controller = HeartRateController(historyStore: store);
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HeartRateHistoryPage(
          controller: controller,
          snapshotWorkerThreshold: 0,
        ),
      ),
    );
    await tester.pump();
    await _waitForChart(tester);

    await tester.tap(find.text('1 小时'));
    await tester.tap(find.text('最多 7 天'));
    await tester.tap(find.text('24 小时'));
    await tester.pump();
    await _waitForChart(tester);

    expect(find.byKey(HeartRateHistoryChart.chartKey), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      controller.dispose();
      await store.flush();
    });
  });

  testWidgets('default 100k pipeline compacts, opens all, and refreshes', (
    tester,
  ) async {
    late Directory directory;
    late HeartRateHistoryStore store;
    late File pointsFile;
    late Duration loadElapsed;
    late Duration compressionElapsed;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp(
        'pulse-history-default-stress-',
      );
      pointsFile = File(
        '${directory.path}${Platform.pathSeparator}'
        'pulse_heart_rate_points.ndjson',
      );
      final buffer = StringBuffer();
      final start = DateTime.now().subtract(const Duration(seconds: 110000));
      for (var index = 0; index < 110000; index++) {
        final recordedAt = start.add(Duration(seconds: index));
        buffer.writeln(
          jsonEncode(<String, Object>{
            'id': recordedAt.microsecondsSinceEpoch.toString(),
            'bpm': 58 + index % 75,
            'recordedAt': recordedAt.toUtc().toIso8601String(),
            'source': 'Default Stress Band',
          }),
        );
      }
      await pointsFile.writeAsString(buffer.toString(), flush: true);
      store = HeartRateHistoryStore(
        directoryProvider: () async => directory,
        saveDelay: const Duration(days: 1),
      );
      final loadStopwatch = Stopwatch()..start();
      await store.load();
      loadStopwatch.stop();
      loadElapsed = loadStopwatch.elapsed;
      expect(store.points, hasLength(100000));

      final compressionStopwatch = Stopwatch()..start();
      await store.flush();
      compressionStopwatch.stop();
      compressionElapsed = compressionStopwatch.elapsed;
      final compactedLines = await pointsFile.readAsLines();
      expect(
        compactedLines.where((line) => line.isNotEmpty),
        hasLength(100000),
      );
    });
    addTearDown(() => deleteDirectoryWithRetry(directory));
    expect(loadElapsed, lessThan(const Duration(seconds: 30)));
    expect(compressionElapsed, lessThan(const Duration(seconds: 30)));

    final controller = HeartRateController(historyStore: store);
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HeartRateHistoryPage(
          controller: controller,
          snapshotWorkerThreshold: 0,
        ),
      ),
    );
    await tester.pump();
    await _waitForChart(tester);

    final allStopwatch = Stopwatch()..start();
    await tester.tap(find.text('本次全部'));
    await tester.pump();
    await _waitForChart(tester);
    allStopwatch.stop();
    expect(allStopwatch.elapsed, lessThan(const Duration(seconds: 30)));

    final refreshStopwatch = Stopwatch()..start();
    for (var index = 0; index < 3; index++) {
      await tester.runAsync(
        () => controller.saveHistoryNote(
          store.points[index * 100].id,
          'refresh $index',
        ),
      );
    }
    await tester.pump();
    expect(find.text('refresh 2'), findsNothing);
    await tester.tap(find.byTooltip('刷新历史'));
    await tester.pump();
    await _waitForText(tester, 'refresh 2');
    refreshStopwatch.stop();
    expect(refreshStopwatch.elapsed, lessThan(const Duration(seconds: 30)));
    expect(find.text('refresh 2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      controller.dispose();
      await store.flush();
    });
  });
}

Future<void> _waitForText(WidgetTester tester, String text) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < const Duration(seconds: 30)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (find.text(text).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Text "$text" did not appear within the stress budget');
}

Future<void> _waitForChart(WidgetTester tester) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < const Duration(seconds: 30)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (find.byKey(HeartRateHistoryChart.chartKey).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('History chart did not finish within the stress budget');
}
