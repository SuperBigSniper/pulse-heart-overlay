import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:heartbeat_monitor/src/heart_rate/heart_rate_history.dart';
import 'package:heartbeat_monitor/src/widgets/heart_rate_history_chart.dart';

void main() {
  test('classifies heart rate zones at the documented boundaries', () {
    expect(heartRateZoneFor(59), HeartRateZone.low);
    expect(heartRateZoneFor(60), HeartRateZone.medium);
    expect(heartRateZoneFor(100), HeartRateZone.medium);
    expect(heartRateZoneFor(101), HeartRateZone.high);
  });

  test('persists every point and point-level note across reloads', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pulse-history-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = HeartRateHistoryStore(
      directoryProvider: () async => directory,
      saveDelay: const Duration(days: 1),
    );
    await store.load();

    final start = DateTime(2026, 11, 3, 8, 30);
    final first = store.addMeasurement(
      beatsPerMinute: 58,
      recordedAt: start,
      source: 'Band A',
    );
    final second = store.addMeasurement(
      beatsPerMinute: 86,
      recordedAt: start.add(const Duration(seconds: 1)),
      source: 'Band A',
    );
    final third = store.addMeasurement(
      beatsPerMinute: 126,
      recordedAt: start.add(const Duration(seconds: 2)),
      source: 'Band A',
    );
    await store.saveNote(
      pointId: second!.id,
      text: '  start climbing  ',
      now: start.add(const Duration(minutes: 1)),
    );
    await store.flush();
    store.dispose();

    final reloaded = HeartRateHistoryStore(
      directoryProvider: () async => directory,
    );
    await reloaded.load();

    expect(reloaded.loadError, isNull);
    expect(reloaded.points, hasLength(3));
    expect(reloaded.points.map((point) => point.beatsPerMinute), <int>[
      58,
      86,
      126,
    ]);
    expect(reloaded.points.map((point) => point.zone), <HeartRateZone>[
      HeartRateZone.low,
      HeartRateZone.medium,
      HeartRateZone.high,
    ]);
    expect(reloaded.noteForPoint(second.id)?.text, 'start climbing');
    expect(reloaded.noteForPoint(first!.id), isNull);
    expect(reloaded.noteForPoint(third!.id), isNull);
    reloaded.dispose();
  });

  test('samples multiple broadcasts in the same second once', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pulse-history-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = HeartRateHistoryStore(
      directoryProvider: () async => directory,
      saveDelay: const Duration(days: 1),
    );
    await store.load();
    final time = DateTime(2026, 11, 3, 9);

    final first = store.addMeasurement(
      beatsPerMinute: 72,
      recordedAt: time,
      source: 'Band A',
    );
    final second = store.addMeasurement(
      beatsPerMinute: 73,
      recordedAt: time,
      source: 'Band A',
    );

    expect(first, isNotNull);
    expect(second, isNull);
    expect(store.points, hasLength(1));
    store.dispose();
  });

  test('persists each device connection as a separate session', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pulse-history-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = HeartRateHistoryStore(
      directoryProvider: () async => directory,
      saveDelay: const Duration(days: 1),
    );
    await store.load();
    final start = DateTime.now().subtract(const Duration(hours: 2));
    final firstSession = store.startSession(
      source: 'Band A',
      deviceId: 'device-a',
      startedAt: start,
    );
    store.addMeasurement(
      beatsPerMinute: 70,
      recordedAt: start.add(const Duration(seconds: 2)),
      source: 'Band A',
      sessionId: firstSession.id,
    );
    store.endSession(
      firstSession.id,
      endedAt: start.add(const Duration(minutes: 1)),
    );
    final secondSession = store.startSession(
      source: 'Band B',
      deviceId: 'device-b',
      startedAt: start.add(const Duration(hours: 1)),
    );
    store.addMeasurement(
      beatsPerMinute: 90,
      recordedAt: start.add(const Duration(hours: 1, seconds: 2)),
      source: 'Band B',
      sessionId: secondSession.id,
    );
    await store.flush();
    store.dispose();

    final reloaded = HeartRateHistoryStore(
      directoryProvider: () async => directory,
    );
    await reloaded.load();
    expect(reloaded.sessions, hasLength(2));
    expect(reloaded.sessions.map((session) => session.source), <String>[
      'Band B',
      'Band A',
    ]);
    expect(reloaded.points.map((point) => point.sessionId), <String>[
      firstSession.id,
      secondSession.id,
    ]);
    expect(reloaded.sessions.last.endedAt, isNotNull);
    reloaded.dispose();
  });

  test('deleting a session removes only its points and notes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pulse-history-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = HeartRateHistoryStore(
      directoryProvider: () async => directory,
      saveDelay: const Duration(days: 1),
    );
    await store.load();
    final start = DateTime.now().subtract(const Duration(hours: 1));
    final first = store.startSession(
      source: 'Band A',
      deviceId: 'device-a',
      startedAt: start,
    );
    final firstPoint = store.addMeasurement(
      beatsPerMinute: 70,
      recordedAt: start.add(const Duration(seconds: 2)),
      source: 'Band A',
      sessionId: first.id,
    )!;
    await store.saveNote(pointId: firstPoint.id, text: 'first');
    store.endSession(first.id);
    final second = store.startSession(
      source: 'Band B',
      deviceId: 'device-b',
      startedAt: start.add(const Duration(minutes: 10)),
    );
    final secondPoint = store.addMeasurement(
      beatsPerMinute: 90,
      recordedAt: start.add(const Duration(minutes: 10, seconds: 2)),
      source: 'Band B',
      sessionId: second.id,
    )!;
    await store.saveNote(pointId: secondPoint.id, text: 'second');

    expect(await store.deleteSession(first.id), isTrue);
    expect(store.sessions.map((session) => session.id), <String>[second.id]);
    expect(store.points.map((point) => point.id), <String>[secondPoint.id]);
    expect(store.noteForPoint(firstPoint.id), isNull);
    expect(store.noteForPoint(secondPoint.id)?.text, 'second');
    store.dispose();
  });

  test('the first pending point starts the save window', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pulse-history-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = HeartRateHistoryStore(
      directoryProvider: () async => directory,
      saveDelay: const Duration(milliseconds: 120),
    );
    await store.load();
    final start = DateTime.now();
    store.addMeasurement(
      beatsPerMinute: 70,
      recordedAt: start,
      source: 'Band A',
    );
    await Future<void>.delayed(const Duration(milliseconds: 70));
    store.addMeasurement(
      beatsPerMinute: 72,
      recordedAt: start.add(const Duration(seconds: 1)),
      source: 'Band A',
    );
    final pointsFile = File(
      '${directory.path}${Platform.pathSeparator}'
      'pulse_heart_rate_points.ndjson',
    );
    for (var attempt = 0; attempt < 20; attempt++) {
      if (await pointsFile.exists()) {
        final lines = await pointsFile.readAsLines();
        if (lines.where((line) => line.isNotEmpty).length >= 2) {
          break;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(await pointsFile.exists(), isTrue);
    expect(
      (await pointsFile.readAsLines()).where((line) => line.isNotEmpty),
      hasLength(2),
    );
    store.dispose();
  });

  test('max pending batch forces an early flush', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pulse-history-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = HeartRateHistoryStore(
      directoryProvider: () async => directory,
      saveDelay: const Duration(days: 1),
      maxPendingPoints: 5,
    );
    await store.load();
    final start = DateTime.now();
    for (var index = 0; index < 5; index++) {
      store.addMeasurement(
        beatsPerMinute: 70 + index,
        recordedAt: start.add(Duration(seconds: index * 2)),
        source: 'Band A',
      );
    }
    for (var attempt = 0; attempt < 20; attempt++) {
      final pointsFile = File(
        '${directory.path}${Platform.pathSeparator}'
        'pulse_heart_rate_points.ndjson',
      );
      if (await pointsFile.exists()) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    final reloaded = HeartRateHistoryStore(
      directoryProvider: () async => directory,
    );
    await reloaded.load();
    expect(reloaded.points, hasLength(5));
    store.dispose();
    reloaded.dispose();
  });

  test('clear all removes persisted points and notes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pulse-history-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = HeartRateHistoryStore(
      directoryProvider: () async => directory,
      saveDelay: const Duration(days: 1),
    );
    await store.load();
    final point = store.addMeasurement(
      beatsPerMinute: 74,
      recordedAt: DateTime(2026, 11, 3, 11),
      source: 'Band A',
    );
    await store.saveNote(pointId: point!.id, text: 'walk');
    await store.flush();

    await store.clearAll();
    store.dispose();

    final reloaded = HeartRateHistoryStore(
      directoryProvider: () async => directory,
    );
    await reloaded.load();
    expect(reloaded.points, isEmpty);
    expect(reloaded.notes, isEmpty);
    reloaded.dispose();
  });

  test('drops readings older than the retention period on load', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pulse-history-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = HeartRateHistoryStore(
      directoryProvider: () async => directory,
      saveDelay: const Duration(days: 1),
      retentionPeriod: const Duration(days: 2),
    );
    await store.load();
    final now = DateTime.now();
    store.addMeasurement(
      beatsPerMinute: 65,
      recordedAt: now.subtract(const Duration(days: 3)),
      source: 'Band A',
    );
    store.addMeasurement(beatsPerMinute: 75, recordedAt: now, source: 'Band A');
    await store.flush();
    store.dispose();

    final reloaded = HeartRateHistoryStore(
      directoryProvider: () async => directory,
      retentionPeriod: const Duration(days: 2),
    );
    await reloaded.load();
    expect(reloaded.points, hasLength(1));
    expect(reloaded.points.single.beatsPerMinute, 75);
    await reloaded.flush();
    reloaded.dispose();
  });

  test('enforces the maximum stored point count', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pulse-history-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = HeartRateHistoryStore(
      directoryProvider: () async => directory,
      saveDelay: const Duration(days: 1),
      maxPoints: 3,
    );
    await store.load();
    final start = DateTime.now().subtract(const Duration(seconds: 10));
    for (var index = 0; index < 6; index++) {
      store.addMeasurement(
        beatsPerMinute: 70 + index,
        recordedAt: start.add(Duration(seconds: index * 2)),
        source: 'Band A',
      );
    }
    await store.flush();
    store.dispose();

    final reloaded = HeartRateHistoryStore(
      directoryProvider: () async => directory,
      maxPoints: 3,
    );
    await reloaded.load();
    expect(reloaded.points, hasLength(3));
    expect(reloaded.points.map((point) => point.beatsPerMinute), <int>[
      73,
      74,
      75,
    ]);
    await reloaded.flush();
    reloaded.dispose();
  });

  test('downsampling preserves extremes, edges, and annotated points', () {
    final start = DateTime(2026, 11, 3, 10);
    final points = List<HeartRateHistoryPoint>.generate(400, (index) {
      final bpm = 70 + (math.sin(index / 7) * 30).round();
      return HeartRateHistoryPoint(
        id: '$index',
        beatsPerMinute: bpm,
        recordedAt: start.add(Duration(seconds: index)),
        source: 'Band A',
      );
    });
    final highest = points.reduce(
      (left, right) =>
          left.beatsPerMinute >= right.beatsPerMinute ? left : right,
    );
    final lowest = points.reduce(
      (left, right) =>
          left.beatsPerMinute <= right.beatsPerMinute ? left : right,
    );
    final marked = points[173];

    final sampled = downsampleHeartRateHistoryPoints(
      points,
      maxPoints: 40,
      pinnedPointIds: {marked.id},
    );

    expect(sampled.length, lessThanOrEqualTo(42));
    expect(sampled, contains(points.first));
    expect(sampled, contains(points.last));
    expect(sampled, contains(highest));
    expect(sampled, contains(lowest));
    expect(sampled, contains(marked));
    expect(
      sampled.map((point) => point.recordedAt),
      orderedEquals(sampled.map((point) => point.recordedAt).toList()..sort()),
    );
  });

  test('chart hit testing selects the point nearest to the tapped time', () {
    final start = DateTime(2026, 11, 3, 10);
    final points = List<HeartRateHistoryPoint>.generate(3, (index) {
      return HeartRateHistoryPoint(
        id: '$index',
        beatsPerMinute: 70 + index * 10,
        recordedAt: start.add(Duration(minutes: index * 10)),
        source: 'Band A',
      );
    });
    const size = Size(800, 330);
    const position = Offset(378, 160);

    expect(nearestHistoryPointAt(position, size, points)?.id, '1');
    expect(nearestHistoryPointAt(const Offset(2, 2), size, points), isNull);
  });
}
