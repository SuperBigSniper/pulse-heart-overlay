import 'dart:math' as math;

Duration heartbeatPeriodFor(int? beatsPerMinute, {double speedScale = 1}) {
  final safeBpm = (beatsPerMinute ?? 72).clamp(30, 220).toDouble();
  final safeSpeedScale = speedScale.clamp(0.4, 2.0).toDouble();
  return Duration(milliseconds: (60000 / safeBpm * safeSpeedScale).round());
}

double smoothHeartRate(double? previous, int next) {
  if (previous == null) {
    return next.toDouble();
  }
  return previous * 0.72 + next * 0.28;
}

double heartbeatImpulse(double progress) {
  final t = progress.clamp(0.0, 1.0);
  return _gaussian(t, center: 0.08, width: 0.032).clamp(0.0, 1.0);
}

double _gaussian(
  double value, {
  required double center,
  required double width,
}) {
  final distance = (value - center) / width;
  return math.exp(-0.5 * distance * distance);
}
