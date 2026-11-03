import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../heart_rate/heart_rate_history.dart';
import '../theme/app_theme.dart';

class HeartRateHistoryChart extends StatefulWidget {
  const HeartRateHistoryChart({
    super.key,
    required this.points,
    required this.selectedPointId,
    required this.onPointSelected,
    this.displayPoints,
    this.minimumBpm,
    this.maximumBpm,
    this.notePointIds = const <String>{},
    this.dataVersion = 0,
    this.height = 330,
  });

  static const chartKey = ValueKey<String>('heart-rate-history-chart');

  final List<HeartRateHistoryPoint> points;
  final String? selectedPointId;
  final ValueChanged<HeartRateHistoryPoint> onPointSelected;
  final List<HeartRateHistoryPoint>? displayPoints;
  final int? minimumBpm;
  final int? maximumBpm;
  final Set<String> notePointIds;
  final int dataVersion;
  final double height;

  @override
  State<HeartRateHistoryChart> createState() => _HeartRateHistoryChartState();
}

class _HeartRateHistoryChartState extends State<HeartRateHistoryChart> {
  List<HeartRateHistoryPoint>? _cachedPoints;
  List<HeartRateHistoryPoint>? _cachedDisplayPoints;
  List<HeartRateHistoryPoint>? _paintedPoints;
  Set<String> _cachedNotePointIds = const <String>{};
  String? _cachedSelectedPointId;
  int _cachedDataVersion = -1;
  int _cachedPointCount = 0;
  int? _lowest;
  int? _highest;

  void _updateChartData() {
    final points = widget.points;
    final selectedId = widget.selectedPointId;
    if (identical(points, _cachedPoints) &&
        _cachedDataVersion == widget.dataVersion &&
        identical(widget.displayPoints, _cachedDisplayPoints) &&
        _cachedPointCount == points.length &&
        _cachedSelectedPointId == selectedId &&
        setEquals(_cachedNotePointIds, widget.notePointIds)) {
      return;
    }
    _cachedPoints = points;
    _cachedDisplayPoints = widget.displayPoints;
    _cachedDataVersion = widget.dataVersion;
    _cachedPointCount = points.length;
    _cachedSelectedPointId = selectedId;
    _cachedNotePointIds = Set<String>.of(widget.notePointIds);
    if (points.isEmpty) {
      _paintedPoints = null;
      _lowest = null;
      _highest = null;
      return;
    }
    final displayPoints = widget.displayPoints;
    if (displayPoints != null) {
      final painted = List<HeartRateHistoryPoint>.of(
        displayPoints,
        growable: true,
      );
      if (selectedId != null &&
          !painted.any((point) => point.id == selectedId)) {
        final selected = _findPointById(points, selectedId);
        if (selected != null) {
          painted.add(selected);
          painted.sort(
            (left, right) => left.recordedAt.compareTo(right.recordedAt),
          );
        }
      }
      _paintedPoints = painted;
    } else {
      final pinnedIds = <String>{...widget.notePointIds};
      if (selectedId != null) {
        pinnedIds.add(selectedId);
      }
      _paintedPoints = downsampleHeartRateHistoryPoints(
        points,
        pinnedPointIds: pinnedIds,
      );
    }
    final providedMinimum = widget.minimumBpm;
    final providedMaximum = widget.maximumBpm;
    late int lowest;
    late int highest;
    if (providedMinimum != null && providedMaximum != null) {
      lowest = providedMinimum;
      highest = providedMaximum;
    } else {
      lowest = points.first.beatsPerMinute;
      highest = lowest;
      for (var index = 1; index < points.length; index++) {
        final bpm = points[index].beatsPerMinute;
        if (bpm < lowest) {
          lowest = bpm;
        }
        if (bpm > highest) {
          highest = bpm;
        }
      }
    }
    _lowest = lowest;
    _highest = highest;
  }

  @override
  Widget build(BuildContext context) {
    _updateChartData();
    final points = widget.points;
    if (points.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.paper,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.line),
          ),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.show_chart, size: 28, color: AppColors.inkMuted),
                SizedBox(height: 10),
                Text(
                  '这个时间范围还没有心率记录',
                  style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final paintedPoints = _paintedPoints ?? points;
    final lowest = _lowest!;
    final highest = _highest!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, widget.height);
        return Semantics(
          label: '心率历史折线图，共 ${points.length} 个点，最低 $lowest，最高 $highest',
          child: GestureDetector(
            key: HeartRateHistoryChart.chartKey,
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final point = nearestHistoryPointAt(
                details.localPosition,
                size,
                points,
              );
              if (point != null) {
                widget.onPointSelected(point);
              }
            },
            child: CustomPaint(
              size: size,
              painter: _HeartRateHistoryChartPainter(
                points: paintedPoints,
                selectedPointId: widget.selectedPointId,
                notePointIds: widget.notePointIds,
                chartStart: points.first.recordedAt,
                chartEnd: points.last.recordedAt,
              ),
            ),
          ),
        );
      },
    );
  }
}

List<HeartRateHistoryPoint> downsampleHeartRateHistoryPoints(
  List<HeartRateHistoryPoint> points, {
  int maxPoints = 1600,
  Set<String> pinnedPointIds = const <String>{},
}) {
  if (points.length <= maxPoints) {
    return points;
  }

  final selected = <String, HeartRateHistoryPoint>{};
  for (final point in points) {
    if (pinnedPointIds.contains(point.id)) {
      selected[point.id] = point;
    }
  }

  final bucketCount = math.max(1, maxPoints ~/ 4);
  final bucketSize = (points.length / bucketCount).ceil();
  for (var start = 0; start < points.length; start += bucketSize) {
    final end = math.min(start + bucketSize, points.length);
    var lowest = points[start];
    var highest = points[start];
    for (var index = start + 1; index < end; index++) {
      final point = points[index];
      if (point.beatsPerMinute < lowest.beatsPerMinute) {
        lowest = point;
      }
      if (point.beatsPerMinute > highest.beatsPerMinute) {
        highest = point;
      }
    }
    selected.putIfAbsent(points[start].id, () => points[start]);
    selected.putIfAbsent(lowest.id, () => lowest);
    selected.putIfAbsent(highest.id, () => highest);
    selected.putIfAbsent(points[end - 1].id, () => points[end - 1]);
  }

  final result = selected.values.toList()
    ..sort((left, right) => left.recordedAt.compareTo(right.recordedAt));
  return result;
}

HeartRateHistoryPoint? nearestHistoryPointAt(
  Offset position,
  Size size,
  List<HeartRateHistoryPoint> points,
) {
  if (points.isEmpty) {
    return null;
  }
  final chartRect = _chartRectFor(size);
  if (!chartRect.contains(position)) {
    return null;
  }
  final start = points.first.recordedAt.microsecondsSinceEpoch;
  final end = points.last.recordedAt.microsecondsSinceEpoch;
  if (end <= start) {
    return points.first;
  }
  final fraction = ((position.dx - chartRect.left) / chartRect.width).clamp(
    0.0,
    1.0,
  );
  final targetMicros = start + ((end - start) * fraction).round();
  var low = 0;
  var high = points.length;
  while (low < high) {
    final middle = low + (high - low) ~/ 2;
    if (points[middle].recordedAt.microsecondsSinceEpoch < targetMicros) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  if (low == 0) {
    return points.first;
  }
  if (low == points.length) {
    return points.last;
  }
  final after = points[low];
  final before = points[low - 1];
  final afterDistance = (after.recordedAt.microsecondsSinceEpoch - targetMicros)
      .abs();
  final beforeDistance =
      (before.recordedAt.microsecondsSinceEpoch - targetMicros).abs();
  return beforeDistance <= afterDistance ? before : after;
}

HeartRateHistoryPoint? _findPointById(
  List<HeartRateHistoryPoint> points,
  String id,
) {
  final target = int.tryParse(id);
  if (target == null) {
    return null;
  }
  var low = 0;
  var high = points.length;
  while (low < high) {
    final middle = low + (high - low) ~/ 2;
    final pointId = int.tryParse(points[middle].id.split('-').first) ?? -1;
    if (pointId < target) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  if (low >= points.length) {
    return null;
  }
  return points[low].id == id ? points[low] : null;
}

Rect _chartRectFor(Size size) {
  return Rect.fromLTRB(16, 18, math.max(16, size.width - 44), size.height - 38);
}

class _HeartRateHistoryChartPainter extends CustomPainter {
  _HeartRateHistoryChartPainter({
    required this.points,
    required this.selectedPointId,
    required this.notePointIds,
    required this.chartStart,
    required this.chartEnd,
  });

  final List<HeartRateHistoryPoint> points;
  final String? selectedPointId;
  final Set<String> notePointIds;
  final DateTime chartStart;
  final DateTime chartEnd;

  @override
  void paint(Canvas canvas, Size size) {
    final chartRect = _chartRectFor(size);
    // `displayPoints` can legitimately arrive as an empty list while the full
    // list is not, and `_paintedPoints` is then a non-null empty list that
    // defeats the `?? points` fallback. Never reduce an empty iterable: fall
    // back to the default scale and let the empty frame paint instead of
    // throwing StateError on every frame.
    var minimumBpm = lowHeartRateThreshold;
    var maximumBpm = highHeartRateThreshold;
    if (points.isNotEmpty) {
      minimumBpm = points.first.beatsPerMinute;
      maximumBpm = minimumBpm;
      for (var index = 1; index < points.length; index++) {
        final bpm = points[index].beatsPerMinute;
        minimumBpm = math.min(minimumBpm, bpm);
        maximumBpm = math.max(maximumBpm, bpm);
      }
    }
    final lowerBpm = math.min(50, minimumBpm - 8).clamp(20, 220).toDouble();
    final upperBpm = math.max(120, maximumBpm + 8).clamp(lowerBpm + 20, 240);

    double yFor(int bpm) {
      final fraction = (bpm - lowerBpm) / (upperBpm - lowerBpm);
      return chartRect.bottom - fraction.clamp(0.0, 1.0) * chartRect.height;
    }

    final highBottom = yFor(highHeartRateThreshold);
    final lowTop = yFor(lowHeartRateThreshold);
    canvas.drawRect(
      Rect.fromLTRB(chartRect.left, chartRect.top, chartRect.right, highBottom),
      Paint()..color = AppColors.coral.withValues(alpha: 0.07),
    );
    canvas.drawRect(
      Rect.fromLTRB(chartRect.left, highBottom, chartRect.right, lowTop),
      Paint()..color = AppColors.mint.withValues(alpha: 0.07),
    );
    canvas.drawRect(
      Rect.fromLTRB(chartRect.left, lowTop, chartRect.right, chartRect.bottom),
      Paint()..color = AppColors.amber.withValues(alpha: 0.07),
    );

    final gridPaint = Paint()
      ..color = AppColors.line.withValues(alpha: 0.9)
      ..strokeWidth = 1;
    for (final threshold in <int>[
      highHeartRateThreshold,
      lowHeartRateThreshold,
    ]) {
      final y = yFor(threshold);
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
    }

    final verticalTicks = size.width >= 620 ? 4 : 2;
    for (var index = 0; index <= verticalTicks; index++) {
      final x = chartRect.left + chartRect.width * index / verticalTicks;
      canvas.drawLine(
        Offset(x, chartRect.top),
        Offset(x, chartRect.bottom),
        gridPaint..color = AppColors.line.withValues(alpha: 0.48),
      );
      final time = _interpolateTime(
        chartStart,
        chartEnd,
        index / verticalTicks,
      );
      _drawText(
        canvas,
        _formatChartTime(time, chartEnd.difference(chartStart)),
        Offset(x, chartRect.bottom + 10),
        _tickAlignment(index, verticalTicks),
        const TextStyle(color: AppColors.inkMuted, fontSize: 9),
      );
    }

    final line = Path();
    final fill = Path();
    Offset? previous;
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final offset = Offset(
        _xFor(chartRect, point.recordedAt),
        yFor(point.beatsPerMinute),
      );
      if (index == 0) {
        line.moveTo(offset.dx, offset.dy);
        fill
          ..moveTo(offset.dx, chartRect.bottom)
          ..lineTo(offset.dx, offset.dy);
      } else {
        line.lineTo(offset.dx, offset.dy);
        fill.lineTo(offset.dx, offset.dy);
      }
      previous = offset;
    }
    if (previous != null) {
      fill
        ..lineTo(previous.dx, chartRect.bottom)
        ..close();
      canvas.drawPath(
        fill,
        Paint()..color = AppColors.ink.withValues(alpha: 0.045),
      );
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    if (points.length <= 500) {
      for (final point in points) {
        if (notePointIds.contains(point.id) || point.id == selectedPointId) {
          continue;
        }
        canvas.drawCircle(
          Offset(
            _xFor(chartRect, point.recordedAt),
            yFor(point.beatsPerMinute),
          ),
          1.6,
          Paint()..color = _zoneColor(point.zone),
        );
      }
    }

    for (final point in points) {
      if (!notePointIds.contains(point.id)) {
        continue;
      }
      final offset = Offset(
        _xFor(chartRect, point.recordedAt),
        yFor(point.beatsPerMinute),
      );
      canvas.drawCircle(offset, 6, Paint()..color = AppColors.surface);
      canvas.drawCircle(
        offset,
        6,
        Paint()
          ..color = AppColors.coralDark
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawCircle(offset, 2.2, Paint()..color = AppColors.coralDark);
    }

    final selected = points
        .where((point) => point.id == selectedPointId)
        .firstOrNull;
    if (selected != null) {
      final offset = Offset(
        _xFor(chartRect, selected.recordedAt),
        yFor(selected.beatsPerMinute),
      );
      canvas.drawCircle(
        offset,
        10,
        Paint()..color = AppColors.surface.withValues(alpha: 0.9),
      );
      canvas.drawCircle(
        offset,
        8,
        Paint()
          ..color = _zoneColor(selected.zone)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.3,
      );
      canvas.drawCircle(
        offset,
        3.5,
        Paint()..color = _zoneColor(selected.zone),
      );
    }

    _drawZoneLabels(canvas, size, chartRect, yFor);
  }

  void _drawZoneLabels(
    Canvas canvas,
    Size size,
    Rect chartRect,
    double Function(int bpm) yFor,
  ) {
    final anchors = <(HeartRateZone, double)>[
      (HeartRateZone.high, (chartRect.top + yFor(highHeartRateThreshold)) / 2),
      (
        HeartRateZone.medium,
        (yFor(highHeartRateThreshold) + yFor(lowHeartRateThreshold)) / 2,
      ),
      (HeartRateZone.low, (yFor(lowHeartRateThreshold) + chartRect.bottom) / 2),
    ];
    for (final anchor in anchors) {
      _drawText(
        canvas,
        anchor.$1.label,
        Offset(size.width - 20, anchor.$2),
        TextAlign.center,
        TextStyle(
          color: _zoneColor(anchor.$1),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    _drawText(
      canvas,
      '$highHeartRateThreshold',
      Offset(size.width - 2, yFor(highHeartRateThreshold)),
      TextAlign.right,
      const TextStyle(color: AppColors.inkMuted, fontSize: 9),
    );
    _drawText(
      canvas,
      '$lowHeartRateThreshold',
      Offset(size.width - 2, yFor(lowHeartRateThreshold)),
      TextAlign.right,
      const TextStyle(color: AppColors.inkMuted, fontSize: 9),
    );
  }

  double _xFor(Rect chartRect, DateTime time) {
    final total =
        chartEnd.microsecondsSinceEpoch - chartStart.microsecondsSinceEpoch;
    if (total <= 0) {
      return chartRect.center.dx;
    }
    final elapsed =
        time.microsecondsSinceEpoch - chartStart.microsecondsSinceEpoch;
    return chartRect.left + chartRect.width * (elapsed / total).clamp(0.0, 1.0);
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset anchor,
    TextAlign alignment,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (alignment) {
      TextAlign.left => anchor.dx,
      TextAlign.right => anchor.dx - painter.width,
      TextAlign.center => anchor.dx - painter.width / 2,
      _ => anchor.dx - painter.width / 2,
    };
    painter.paint(canvas, Offset(dx, anchor.dy - painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant _HeartRateHistoryChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.selectedPointId != selectedPointId ||
        oldDelegate.notePointIds != notePointIds ||
        oldDelegate.chartStart != chartStart ||
        oldDelegate.chartEnd != chartEnd;
  }
}

Color _zoneColor(HeartRateZone zone) {
  return switch (zone) {
    HeartRateZone.low => AppColors.amber,
    HeartRateZone.medium => AppColors.mint,
    HeartRateZone.high => AppColors.coral,
  };
}

TextAlign _tickAlignment(int index, int tickCount) {
  if (index == 0) {
    return TextAlign.left;
  }
  if (index == tickCount) {
    return TextAlign.right;
  }
  return TextAlign.center;
}

DateTime _interpolateTime(DateTime start, DateTime end, double fraction) {
  final span = end.difference(start);
  return start.add(
    Duration(microseconds: (span.inMicroseconds * fraction).round()),
  );
}

String _formatChartTime(DateTime time, Duration span) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  if (span >= const Duration(days: 2)) {
    return '${time.month}/${time.day}';
  }
  return '$hour:$minute';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
