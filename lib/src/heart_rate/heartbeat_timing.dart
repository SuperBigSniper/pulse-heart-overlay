import 'dart:math' as math;

Duration heartbeatPeriodFor(int? beatsPerMinute) {
  final safeBpm = (beatsPerMinute ?? 72).clamp(30, 220).toDouble();
  return Duration(milliseconds: (60000 / safeBpm).round());
}

double smoothHeartRate(double? previous, int next) {
  if (previous == null) {
    return next.toDouble();
  }
  return previous * 0.72 + next * 0.28;
}

double heartbeatImpulse(double progress) {
  final t = progress.clamp(0.0, 1.0);
  final firstBeat = _gaussian(t, center: 0.08, width: 0.032);
  final secondBeat = _gaussian(t, center: 0.255, width: 0.052) * 0.58;
  return (firstBeat + secondBeat).clamp(0.0, 1.0);
}

double _gaussian(
  double value, {
  required double center,
  required double width,
}) {
  final distance = (value - center) / width;
  return math.exp(-0.5 * distance * distance);
}
