import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../heart_rate/heartbeat_timing.dart';
import '../theme/app_theme.dart';

class HeartbeatVisualizer extends StatefulWidget {
  const HeartbeatVisualizer({
    super.key,
    required this.beatsPerMinute,
    required this.active,
    required this.size,
    this.demo = false,
    this.showGuides = true,
    this.showShadow = true,
    this.speedScale = 1,
  });

  final int? beatsPerMinute;
  final bool active;
  final double size;
  final bool demo;
  final bool showGuides;
  final bool showShadow;
  final double speedScale;

  @override
  State<HeartbeatVisualizer> createState() => _HeartbeatVisualizerState();
}

class _HeartbeatVisualizerState extends State<HeartbeatVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration)
      ..repeat();
  }

  Duration get _duration {
    if (!widget.active) {
      return const Duration(milliseconds: 2600);
    }
    return heartbeatPeriodFor(
      widget.beatsPerMinute,
      speedScale: widget.speedScale,
    );
  }

  @override
  void didUpdateWidget(covariant HeartbeatVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active ||
        oldWidget.beatsPerMinute != widget.beatsPerMinute ||
        oldWidget.speedScale != widget.speedScale) {
      _controller.duration = _duration;
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.active && widget.beatsPerMinute != null
          ? '当前心率 ${widget.beatsPerMinute} 次每分钟'
          : '等待心率数据',
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                painter: _HeartbeatPainter(
                  progress: _controller.value,
                  active: widget.active,
                  demo: widget.demo,
                  showGuides: widget.showGuides,
                  showShadow: widget.showShadow,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HeartbeatPainter extends CustomPainter {
  _HeartbeatPainter({
    required this.progress,
    required this.active,
    required this.demo,
    required this.showGuides,
    required this.showShadow,
  });

  final double progress;
  final bool active;
  final bool demo;
  final bool showGuides;
  final bool showShadow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.51);
    final radius = size.shortestSide / 2;
    final impulse = active
        ? heartbeatImpulse(progress)
        : (math.sin(progress * math.pi * 2) + 1) / 2 * 0.12;
    final accent = demo ? AppColors.amber : AppColors.coral;

    if (showGuides) {
      _paintGuides(canvas, center, radius, impulse, accent);
    }

    final scale = active ? 1.0 + impulse * 0.085 : 1.0;
    final heartPath = _buildHeartPath(center, radius * 0.46);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);
    if (showShadow) {
      canvas.drawShadow(
        heartPath,
        accent.withValues(alpha: active ? 0.40 : 0.16),
        active ? 20 : 10,
        true,
      );
    }
    canvas.drawPath(heartPath, Paint()..color = accent);
    _paintHeartHighlight(canvas, center, radius, accent);
    canvas.restore();
  }

  void _paintGuides(
    Canvas canvas,
    Offset center,
    double radius,
    double impulse,
    Color accent,
  ) {
    final guidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.ink.withValues(alpha: 0.08);
    canvas.drawCircle(center, radius * 0.42, guidePaint);
    canvas.drawCircle(center, radius * 0.66, guidePaint);
    canvas.drawCircle(center, radius * 0.91, guidePaint);

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2
      ..color = AppColors.ink.withValues(alpha: 0.28);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.91),
      -math.pi * 0.84,
      math.pi * 0.22,
      false,
      arcPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.91),
      math.pi * 0.16,
      math.pi * 0.22,
      false,
      arcPaint,
    );

    final pulseOpacity = active ? impulse * 0.26 : 0.04;
    canvas.drawCircle(
      center,
      radius * (0.50 + impulse * 0.30),
      Paint()..color = accent.withValues(alpha: pulseOpacity),
    );
    canvas.drawCircle(
      center,
      radius * (0.58 + impulse * 0.18),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = accent.withValues(alpha: pulseOpacity * 1.8),
    );
  }

  void _paintHeartHighlight(
    Canvas canvas,
    Offset center,
    double radius,
    Color accent,
  ) {
    final highlight = Path()
      ..moveTo(center.dx - radius * 0.21, center.dy - radius * 0.18)
      ..cubicTo(
        center.dx - radius * 0.15,
        center.dy - radius * 0.29,
        center.dx - radius * 0.02,
        center.dy - radius * 0.29,
        center.dx + radius * 0.01,
        center.dy - radius * 0.17,
      );
    canvas.drawPath(
      highlight,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.022
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.42),
    );
  }

  Path _buildHeartPath(Offset center, double scale) {
    final path = Path()
      ..moveTo(center.dx, center.dy + scale * 0.92)
      ..cubicTo(
        center.dx - scale * 1.05,
        center.dy + scale * 0.28,
        center.dx - scale * 1.18,
        center.dy - scale * 0.56,
        center.dx - scale * 0.55,
        center.dy - scale * 0.70,
      )
      ..cubicTo(
        center.dx - scale * 0.20,
        center.dy - scale * 0.78,
        center.dx,
        center.dy - scale * 0.45,
        center.dx,
        center.dy - scale * 0.32,
      )
      ..cubicTo(
        center.dx,
        center.dy - scale * 0.45,
        center.dx + scale * 0.20,
        center.dy - scale * 0.78,
        center.dx + scale * 0.55,
        center.dy - scale * 0.70,
      )
      ..cubicTo(
        center.dx + scale * 1.18,
        center.dy - scale * 0.56,
        center.dx + scale * 1.05,
        center.dy + scale * 0.28,
        center.dx,
        center.dy + scale * 0.92,
      )
      ..close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _HeartbeatPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.active != active ||
        oldDelegate.demo != demo ||
        oldDelegate.showGuides != showGuides ||
        oldDelegate.showShadow != showShadow;
  }
}

class EcgLine extends StatefulWidget {
  const EcgLine({
    super.key,
    required this.beatsPerMinute,
    required this.active,
    this.color = AppColors.coral,
    this.speedScale = 1,
  });

  final int? beatsPerMinute;
  final bool active;
  final Color color;
  final double speedScale;

  @override
  State<EcgLine> createState() => _EcgLineState();
}

class _EcgLineState extends State<EcgLine> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: heartbeatPeriodFor(
        widget.beatsPerMinute,
        speedScale: widget.speedScale,
      ),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant EcgLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.beatsPerMinute != widget.beatsPerMinute ||
        oldWidget.active != widget.active ||
        oldWidget.speedScale != widget.speedScale) {
      _controller.duration = heartbeatPeriodFor(
        widget.beatsPerMinute,
        speedScale: widget.speedScale,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _EcgPainter(
            progress: _controller.value,
            active: widget.active,
            color: widget.color,
          ),
        );
      },
    );
  }
}

class _EcgPainter extends CustomPainter {
  _EcgPainter({
    required this.progress,
    required this.active,
    required this.color,
  });

  final double progress;
  final bool active;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final path = Path();
    const sampleCount = 180;

    for (var index = 0; index <= sampleCount; index++) {
      final x = index / sampleCount * size.width;
      final cycle = (index / sampleCount + progress) % 1;
      final value = active ? _ecgValue(cycle) : 0.0;
      final y = centerY - value * size.height * 0.21;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      Paint()
        ..color = AppColors.ink.withValues(alpha: 0.08)
        ..strokeWidth = 1,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 3.2 : 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: active ? 0.72 : 0.20),
    );
  }

  double _ecgValue(double t) {
    final pWave = _bump(t, 0.08, 0.025, 0.18);
    final qWave = _bump(t, 0.205, 0.012, -0.35);
    final rWave = _bump(t, 0.235, 0.012, 1.0);
    final sWave = _bump(t, 0.265, 0.016, -0.46);
    final tWave = _bump(t, 0.38, 0.045, 0.23);
    return pWave + qWave + rWave + sWave + tWave;
  }

  double _bump(double value, double center, double width, double height) {
    final distance = (value - center) / width;
    return math.exp(-0.5 * distance * distance) * height;
  }

  @override
  bool shouldRepaint(covariant _EcgPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.active != active ||
        oldDelegate.color != color;
  }
}
