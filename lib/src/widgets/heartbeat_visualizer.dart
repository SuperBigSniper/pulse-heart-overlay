import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../heart_rate/heartbeat_timing.dart';
import '../theme/app_theme.dart';

class HeartbeatMotion extends StatefulWidget {
  const HeartbeatMotion({
    super.key,
    required this.beatsPerMinute,
    required this.active,
    this.speedScale = 1,
    required this.builder,
  });

  final int? beatsPerMinute;
  final bool active;
  final double speedScale;
  final Widget Function(BuildContext context, Animation<double> animation)
  builder;

  @override
  State<HeartbeatMotion> createState() => _HeartbeatMotionState();
}

class _HeartbeatMotionState extends State<HeartbeatMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final FrameLimitedAnimation _limitedAnimation;
  bool _reducedMotion = false;

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
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration)
      ..value = 0;
    _limitedAnimation = FrameLimitedAnimation(_controller);
    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Custom AnimationControllers do not respond to the system's
    // reduce-motion setting automatically; honor it explicitly. A static
    // rest pose keeps the semantics (current scale, BPM text) without a
    // continuously pulsing animation.
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced != _reducedMotion) {
      _reducedMotion = reduced;
      _restartWithCurrentPhase();
    }
  }

  @override
  void didUpdateWidget(covariant HeartbeatMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active ||
        oldWidget.beatsPerMinute != widget.beatsPerMinute ||
        oldWidget.speedScale != widget.speedScale) {
      _restartWithCurrentPhase();
    }
  }

  void _restartWithCurrentPhase() {
    _controller.duration = _duration;
    if (!widget.active) {
      _controller.stop();
      return;
    }
    if (_reducedMotion) {
      _controller.stop();
      _controller.value = 0.1;
      return;
    }
    _controller.repeat(period: _duration);
  }

  @override
  void dispose() {
    _limitedAnimation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _limitedAnimation);
  }
}

/// [AnimationController] 的轻量代理，向下游隐藏具体 controller 实现。
///
/// 注意：不要在这里做降帧（限 maxFPS）。AnimationController 本身是 vsync
/// 驱动的，每帧只回调一次；在高刷屏（120Hz）上限帧会让动画每两帧才更新
/// 一次，产生明显 judder；帧时间戳抖动还会造成不规律丢帧。保持每帧透传
/// 即可跟随屏幕刷新率，绘制成本由 RepaintBoundary 控制。
class FrameLimitedAnimation extends Animation<double> {
  FrameLimitedAnimation(this._parent)
    : _value = _parent.value {
    _status = _parent.status;
    _parent.addListener(_handleParentValue);
    _parent.addStatusListener(_handleParentStatus);
  }

  final Animation<double> _parent;
  final Set<VoidCallback> _listeners = <VoidCallback>{};
  final Set<AnimationStatusListener> _statusListeners =
      <AnimationStatusListener>{};

  late double _value;
  AnimationStatus _status = AnimationStatus.forward;
  bool _disposed = false;

  @override
  double get value => _value;

  @override
  AnimationStatus get status => _status;

  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  @override
  void addStatusListener(AnimationStatusListener listener) {
    _statusListeners.add(listener);
  }

  @override
  void removeStatusListener(AnimationStatusListener listener) {
    _statusListeners.remove(listener);
  }

  void _handleParentValue() {
    if (_disposed) {
      return;
    }
    _emitValue();
  }

  void _handleParentStatus(AnimationStatus status) {
    if (_disposed || status == _status) {
      return;
    }
    _status = status;
    _emitValue();
    for (final listener in List<AnimationStatusListener>.of(_statusListeners)) {
      listener(status);
    }
  }

  void _emitValue() {
    _value = _parent.value;
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  void dispose() {
    _disposed = true;
    _parent.removeListener(_handleParentValue);
    _parent.removeStatusListener(_handleParentStatus);
    _listeners.clear();
    _statusListeners.clear();
  }
}

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
    this.animation,
  });

  final int? beatsPerMinute;
  final bool active;
  final double size;
  final bool demo;
  final bool showGuides;
  final bool showShadow;
  final double speedScale;
  final Animation<double>? animation;

  @override
  State<HeartbeatVisualizer> createState() => _HeartbeatVisualizerState();
}

class _HeartbeatVisualizerState extends State<HeartbeatVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final FrameLimitedAnimation _limitedController;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
    _limitedController = FrameLimitedAnimation(_controller);
    if (widget.animation == null) {
      if (widget.active) {
        _controller.repeat();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.animation != null) {
      return;
    }
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced != _reducedMotion) {
      _reducedMotion = reduced;
      _restartWithCurrentPhase();
    }
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
    if (oldWidget.animation == null && widget.animation != null) {
      _controller.stop();
      return;
    }
    if (oldWidget.animation != null && widget.animation == null) {
      _restartWithCurrentPhase();
      return;
    }
    if (widget.animation != null) {
      return;
    }
    if (oldWidget.active != widget.active ||
        oldWidget.beatsPerMinute != widget.beatsPerMinute ||
        oldWidget.speedScale != widget.speedScale) {
      _restartWithCurrentPhase();
    }
  }

  void _restartWithCurrentPhase() {
    _controller.duration = _duration;
    if (!widget.active) {
      _controller.stop();
      return;
    }
    if (_reducedMotion) {
      _controller.stop();
      _controller.value = 0.1;
      return;
    }
    _controller.repeat(period: _duration);
  }

  @override
  void dispose() {
    _limitedController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animation = widget.animation ?? _limitedController;
    return Semantics(
      label: widget.active && widget.beatsPerMinute != null
          ? '当前心率 ${widget.beatsPerMinute} 次每分钟'
          : '等待心率数据',
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              return CustomPaint(
                painter: _HeartbeatPainter(
                  progress: animation.value,
                  strength: heartbeatStrengthFor(widget.beatsPerMinute),
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
    required this.strength,
    required this.active,
    required this.demo,
    required this.showGuides,
    required this.showShadow,
  });

  final double progress;
  final double strength;
  final bool active;
  final bool demo;
  final bool showGuides;
  final bool showShadow;

  // Geometry only changes when the widget is resized; the pulse is applied by
  // scaling on the canvas, so the paths can be cached across frames. This
  // painter runs at screen refresh rate in the always-on game overlay, where
  // per-frame Path allocation is the hottest avoidable cost.
  static (Offset, double)? _heartPathKey;
  static Path? _heartPath;
  static (Offset, double)? _highlightKey;
  static Path? _highlightPath;

  // Shared paints: the UI thread is single-threaded and each paint is consumed
  // immediately after mutation, so instances can be reused across frames.
  static final Paint _guidePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = AppColors.ink.withValues(alpha: 0.08);
  static final Paint _arcPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 2
    ..color = AppColors.ink.withValues(alpha: 0.28);
  static final Paint _inkShadowPaint = Paint()
    ..color = AppColors.ink.withValues(alpha: 0.05);
  static final Paint _highlightPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..color = Colors.white.withValues(alpha: 0.42);
  static final Paint _pulseFillPaint = Paint();
  static final Paint _pulseStrokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  static final Map<Color, Paint> _accentPaints = <Color, Paint>{};

  static Paint _accentPaint(Color color) {
    return _accentPaints.putIfAbsent(color, () => Paint()..color = color);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.51);
    final radius = size.shortestSide / 2;
    final impulse = active
        ? heartbeatImpulse(progress)
        : (math.sin(progress * math.pi * 2) + 1) / 2 * 0.12;
    final accent = demo ? AppColors.amber : AppColors.coral;

    if (showGuides) {
      _paintGuides(canvas, center, radius, impulse, strength, accent);
    }

    final scale = active ? 1.0 + impulse * strength : 1.0;
    final heartPath = _heartPathFor(center, radius * 0.46);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);
    if (showShadow) {
      // Draw the shifted copies via canvas.translate instead of Path.shift so
      // the cached path is reused without allocating a shifted copy per frame.
      canvas.save();
      canvas.translate(0, radius * (active ? 0.045 : 0.025));
      canvas.drawPath(
        heartPath,
        _accentPaint(accent.withValues(alpha: active ? 0.12 : 0.06)),
      );
      canvas.restore();
      canvas.save();
      canvas.translate(0, radius * 0.018);
      canvas.drawPath(heartPath, _inkShadowPaint);
      canvas.restore();
    }
    canvas.drawPath(heartPath, _accentPaint(accent));
    _paintHeartHighlight(canvas, center, radius);
    canvas.restore();
  }

  static Path _heartPathFor(Offset center, double scale) {
    final key = (center, scale);
    final cached = _heartPath;
    if (cached != null && _heartPathKey == key) {
      return cached;
    }
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
    _heartPathKey = key;
    _heartPath = path;
    return path;
  }

  void _paintGuides(
    Canvas canvas,
    Offset center,
    double radius,
    double impulse,
    double strength,
    Color accent,
  ) {
    canvas.drawCircle(center, radius * 0.42, _guidePaint);
    canvas.drawCircle(center, radius * 0.66, _guidePaint);
    canvas.drawCircle(center, radius * 0.91, _guidePaint);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.91),
      -math.pi * 0.84,
      math.pi * 0.22,
      false,
      _arcPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.91),
      math.pi * 0.16,
      math.pi * 0.22,
      false,
      _arcPaint,
    );

    final pulseOpacity = active ? impulse * (0.15 + strength * 1.1) : 0.04;
    canvas.drawCircle(
      center,
      radius * (0.50 + impulse * 0.30),
      _pulseFillPaint
        ..color = accent.withValues(alpha: pulseOpacity),
    );
    canvas.drawCircle(
      center,
      radius * (0.58 + impulse * 0.18),
      _pulseStrokePaint
        ..color = accent.withValues(alpha: pulseOpacity * 1.8),
    );
  }

  void _paintHeartHighlight(Canvas canvas, Offset center, double radius) {
    final key = (center, radius);
    final cached = _highlightPath;
    Path highlight;
    if (cached != null && _highlightKey == key) {
      highlight = cached;
    } else {
      highlight =
          Path()
            ..moveTo(center.dx - radius * 0.21, center.dy - radius * 0.18)
            ..cubicTo(
              center.dx - radius * 0.15,
              center.dy - radius * 0.29,
              center.dx - radius * 0.02,
              center.dy - radius * 0.29,
              center.dx + radius * 0.01,
              center.dy - radius * 0.17,
            );
      _highlightKey = key;
      _highlightPath = highlight;
    }
    canvas.drawPath(
      highlight,
      _highlightPaint..strokeWidth = radius * 0.022,
    );
  }

  @override
  bool shouldRepaint(covariant _HeartbeatPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strength != strength ||
        oldDelegate.active != active ||
        oldDelegate.demo != demo ||
        oldDelegate.showGuides != showGuides ||
        oldDelegate.showShadow != showShadow;
  }
}

class EcgLine extends StatelessWidget {
  const EcgLine({
    super.key,
    required this.animation,
    required this.beatsPerMinute,
    required this.active,
    this.color = AppColors.coral,
    this.verticalAlignment = 0.5,
  });

  final Animation<double> animation;
  final int? beatsPerMinute;
  final bool active;
  final Color color;
  final double verticalAlignment;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          return CustomPaint(
            painter: _EcgPainter(
              progress: animation.value,
              strength: heartbeatStrengthFor(beatsPerMinute),
              active: active,
              color: color,
              verticalAlignment: verticalAlignment,
            ),
          );
        },
      ),
    );
  }
}

class _EcgPainter extends CustomPainter {
  static const _sampleCount = 180;
  static final List<double> _waveform = List<double>.generate(
    _sampleCount + 1,
    (index) => _ecgValue(index / _sampleCount),
    growable: false,
  );

  // Shared paints, mutated per frame on the single-threaded UI thread.
  static final Paint _baselinePaint = Paint()..strokeWidth = 1;
  static final Paint _glowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = 7;
  static final Paint _linePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  _EcgPainter({
    required this.progress,
    required this.strength,
    required this.active,
    required this.color,
    required this.verticalAlignment,
  });

  final double progress;
  final double strength;
  final bool active;
  final Color color;
  final double verticalAlignment;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height * verticalAlignment;
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      _baselinePaint
        ..color = AppColors.ink.withValues(alpha: active ? 0.08 : 0.05),
    );
    if (!active) {
      return;
    }

    final path = Path();
    final impulse = heartbeatImpulse(progress);
    final waveScale = 1.0 + impulse * strength * 1.8;
    final amplitude = size.height * 0.21 * waveScale;
    final step = size.width / _sampleCount;

    for (var index = 0; index <= _sampleCount; index++) {
      final cycle = ecgCycleFor(index / _sampleCount, progress);
      final sampleIndex = (cycle * _sampleCount)
          .round()
          .clamp(0, _sampleCount)
          .toInt();
      final value = _waveform[sampleIndex];
      final y = centerY - value * amplitude;
      if (index == 0) {
        path.moveTo(0, y);
      } else {
        path.lineTo(index * step, y);
      }
    }

    if (impulse > 0.01) {
      canvas.drawPath(
        path,
        _glowPaint
          ..strokeWidth = 7
          ..color = color.withValues(alpha: impulse * (0.08 + strength * 0.6)),
      );
    }
    canvas.drawPath(
      path,
      _linePaint
        ..strokeWidth = 2.8 + impulse * strength * 8
        ..color = color.withValues(alpha: 0.54 + impulse * 0.26),
    );
  }

  static double _ecgValue(double t) {
    final pWave = _bump(t, 0.08, 0.025, 0.18);
    final qWave = _bump(t, 0.205, 0.012, -0.35);
    final rWave = _bump(t, 0.235, 0.012, 1.0);
    final sWave = _bump(t, 0.265, 0.016, -0.46);
    final tWave = _bump(t, 0.38, 0.045, 0.23);
    return pWave + qWave + rWave + sWave + tWave;
  }

  static double _bump(
    double value,
    double center,
    double width,
    double height,
  ) {
    final distance = (value - center) / width;
    return math.exp(-0.5 * distance * distance) * height;
  }

  @override
  bool shouldRepaint(covariant _EcgPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strength != strength ||
        oldDelegate.active != active ||
        oldDelegate.color != color ||
        oldDelegate.verticalAlignment != verticalAlignment;
  }
}
