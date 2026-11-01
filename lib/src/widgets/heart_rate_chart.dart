import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../heart_rate/heart_rate_controller.dart';
import '../theme/app_theme.dart';

class HeartRateChart extends StatelessWidget {
  const HeartRateChart({super.key, required this.samples, this.height = 136});

  final List<HeartRateSample> samples;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (samples.length < 2) {
      return SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.paper,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.line),
          ),
          child: const Center(
            child: Text(
              '等待连续心率数据',
              style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
            ),
          ),
        ),
      );
    }

    final values = samples.map((sample) => sample.beatsPerMinute).toList();
    final minimum = values.reduce(math.min);
    final maximum = values.reduce(math.max);

    return Semantics(
      label: '心率趋势，最低 $minimum，最高 $maximum',
      child: SizedBox(
        height: height,
        child: CustomPaint(
          painter: _HeartRateChartPainter(
            values: values,
            minimum: minimum,
            maximum: maximum,
          ),
        ),
      ),
    );
  }
}

class _HeartRateChartPainter extends CustomPainter {
  _HeartRateChartPainter({
    required this.values,
    required this.minimum,
    required this.maximum,
  });

  final List<int> values;
  final int minimum;
  final int maximum;

  @override
  void paint(Canvas canvas, Size size) {
    final chartRect = Rect.fromLTWH(0, 8, size.width, size.height - 24);
    final gridPaint = Paint()
      ..color = AppColors.line.withValues(alpha: 0.8)
      ..strokeWidth = 1;

    for (var index = 0; index < 3; index++) {
      final y = chartRect.top + chartRect.height * index / 2;
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
    }

    final range = math.max(maximum - minimum, 12);
    final padding = math.max(range * 0.22, 3);
    final low = minimum - padding;
    final high = maximum + padding;

    final linePath = Path();
    final fillPath = Path();
    Offset? lastPoint;

    for (var index = 0; index < values.length; index++) {
      final x =
          chartRect.left +
          chartRect.width * index / math.max(values.length - 1, 1);
      final normalized = (values[index] - low) / (high - low);
      final y = chartRect.bottom - normalized * chartRect.height;
      final point = Offset(x, y);
      if (index == 0) {
        linePath.moveTo(point.dx, point.dy);
        fillPath
          ..moveTo(point.dx, chartRect.bottom)
          ..lineTo(point.dx, point.dy);
      } else {
        linePath.lineTo(point.dx, point.dy);
        fillPath.lineTo(point.dx, point.dy);
      }
      lastPoint = point;
    }

    if (lastPoint != null) {
      fillPath
        ..lineTo(lastPoint.dx, chartRect.bottom)
        ..close();
      canvas.drawPath(
        fillPath,
        Paint()..color = AppColors.coral.withValues(alpha: 0.09),
      );
    }

    canvas.drawPath(
      linePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = AppColors.coral,
    );

    if (lastPoint != null) {
      canvas.drawCircle(lastPoint, 5, Paint()..color = AppColors.surface);
      canvas.drawCircle(lastPoint, 3.3, Paint()..color = AppColors.coral);
    }

    _drawRangeLabel(
      canvas,
      '${maximum.round()}',
      Offset(size.width - 2, chartRect.top),
      Alignment.centerRight,
    );
    _drawRangeLabel(
      canvas,
      '${minimum.round()}',
      Offset(size.width - 2, chartRect.bottom),
      Alignment.centerRight,
    );
  }

  void _drawRangeLabel(
    Canvas canvas,
    String text,
    Offset anchor,
    Alignment alignment,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: AppColors.inkMuted,
          fontSize: 10,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = anchor.dx - painter.width;
    final dy = anchor.dy - painter.height / 2;
    painter.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _HeartRateChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.minimum != minimum ||
        oldDelegate.maximum != maximum;
  }
}
