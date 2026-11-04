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
  testWidgets('selecting a point stores and displays its note', (tester) async {
    final start = DateTime.now().subtract(const Duration(minutes: 20));
    late Directory directory;
    late HeartRateHistoryStore store;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp(
        'pulse-history-page-test-',
      );
      store = HeartRateHistoryStore(
        directoryProvider: () async => directory,
        saveDelay: const Duration(days: 1),
      );
      await store.load();
      for (var index = 0; index < 3; index++) {
        store.addMeasurement(
          beatsPerMinute: 68 + index * 20,
          recordedAt: start.add(Duration(minutes: index * 10)),
          source: 'Test Band',
        );
      }
      await store.flush();
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
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(HeartRateHistoryChart.chartKey), findsOneWidget);
    await tester.tap(find.byKey(HeartRateHistoryChart.chartKey));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '开始爬楼');
    await tester.tap(find.text('添加备注'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.savedHistoryNotes, hasLength(1));
    expect(controller.savedHistoryNotes.single.text, '开始爬楼');
    expect(find.text('开始爬楼'), findsWidgets);
    expect(tester.takeException(), isNull);

    store.addMeasurement(
      beatsPerMinute: 80,
      recordedAt: DateTime.now(),
      source: 'Test Band',
    );
    controller.savedHistoryChanges.value++;
    await tester.pump();
    expect(find.textContaining('3 个心率点'), findsOneWidget);

    await tester.tap(find.byTooltip('刷新历史'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('4 个心率点'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(900, 640));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      controller.dispose();
      await store.flush();
    });
  });

  testWidgets('closing history resumes live widgets after unmounting', (
    tester,
  ) async {
    late Directory directory;
    late HeartRateHistoryStore store;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp(
        'pulse-history-navigation-test-',
      );
      store = HeartRateHistoryStore(
        directoryProvider: () async => directory,
        saveDelay: const Duration(days: 1),
      );
      await store.load();
    });
    addTearDown(() => deleteDirectoryWithRetry(directory));
    final controller = HeartRateController(historyStore: store);
    final connectionRevision = controller.connectionChanges.value;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: controller.connectionChanges,
            builder: (context, revision, child) {
              return Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (context) =>
                            HeartRateHistoryPage(controller: controller),
                      ),
                    );
                  },
                  child: Text('打开历史 $revision'),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开历史 $connectionRevision'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(controller.connectionChanges.value, greaterThan(connectionRevision));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      controller.dispose();
      await store.flush();
    });
  });

  testWidgets('an open history page follows new points on its own', (
    tester,
  ) async {
    late Directory directory;
    late HeartRateHistoryStore store;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp(
        'pulse-history-live-test-',
      );
      store = HeartRateHistoryStore(
        directoryProvider: () async => directory,
        saveDelay: const Duration(days: 1),
      );
      await store.load();
      final start = DateTime.now().subtract(const Duration(minutes: 30));
      for (var index = 0; index < 3; index++) {
        store.addMeasurement(
          beatsPerMinute: 70 + index,
          recordedAt: start.add(Duration(minutes: index * 10)),
          source: 'Live Band',
          sessionId: 'live-session',
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
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('3 个心率点'), findsOneWidget);

    // A reading lands while the page stays open: no tap on 刷新.
    store.addMeasurement(
      beatsPerMinute: 88,
      recordedAt: DateTime.now(),
      source: 'Live Band',
      sessionId: 'live-session',
    );
    controller.savedHistoryChanges.value++;
    await tester.pump();
    expect(find.textContaining('3 个心率点'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 950));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('4 个心率点'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      controller.dispose();
      await store.flush();
    });
  });

  testWidgets('history switches between separate connection sessions', (
    tester,
  ) async {
    late Directory directory;
    late HeartRateHistoryStore store;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp(
        'pulse-history-session-test-',
      );
      store = HeartRateHistoryStore(
        directoryProvider: () async => directory,
        saveDelay: const Duration(days: 1),
      );
      await store.load();
      final start = DateTime.now().subtract(const Duration(hours: 2));
      final first = store.startSession(
        source: 'Band A',
        deviceId: 'device-a',
        startedAt: start,
      );
      store.addMeasurement(
        beatsPerMinute: 70,
        recordedAt: start.add(const Duration(seconds: 2)),
        source: 'Band A',
        sessionId: first.id,
      );
      store.endSession(
        first.id,
        endedAt: start.add(const Duration(minutes: 1)),
      );
      final second = store.startSession(
        source: 'Band B',
        deviceId: 'device-b',
        startedAt: start.add(const Duration(hours: 1)),
      );
      for (var index = 0; index < 2; index++) {
        store.addMeasurement(
          beatsPerMinute: 85 + index,
          recordedAt: start.add(Duration(hours: 1, seconds: 2 + index * 2)),
          source: 'Band B',
          sessionId: second.id,
        );
      }
    });
    addTearDown(() => deleteDirectoryWithRetry(directory));
    final controller = HeartRateController(historyStore: store);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HeartRateHistoryPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Band B'), findsOneWidget);
    expect(find.textContaining('2 个心率点'), findsOneWidget);
    await tester.tap(find.textContaining('Band A'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Band A'), findsOneWidget);
    expect(find.textContaining('1 个心率点'), findsOneWidget);

    await tester.tap(find.byTooltip('删除会话'));
    await tester.pumpAndSettle();
    expect(find.text('删除这个连接会话？'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pump();
    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (find.textContaining('Band A').evaluate().isEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('Band A'), findsNothing);
    expect(store.sessions, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      controller.dispose();
      await store.flush();
    });
  });
}
