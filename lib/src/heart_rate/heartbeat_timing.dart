import 'dart:math' as math;

const _ecgCenterOffset = 0.27;
const minimumHeartbeatSpeedScale = 0.5;
const maximumHeartbeatSpeedScale = 2.0;

double visualHeartbeatRateFor(int? beatsPerMinute, {double speedScale = 1}) {
  final bpm = (beatsPerMinute ?? 60).clamp(30, 220).toDouble();
  final safeSpeedScale = speedScale
      .clamp(minimumHeartbeatSpeedScale, maximumHeartbeatSpeedScale)
      .toDouble();
  return bpm / 60 * safeSpeedScale;
}

Duration heartbeatPeriodFor(int? beatsPerMinute, {double speedScale = 1}) {
  return Duration(
    milliseconds:
        (1000 / visualHeartbeatRateFor(beatsPerMinute, speedScale: speedScale))
            .round(),
  );
}

double heartbeatStrengthFor(int? beatsPerMinute) {
  final safeBpm = (beatsPerMinute ?? 72).clamp(30, 220).toDouble();
  final intensity = ((safeBpm - 45) / 80).clamp(0.0, 1.0);
  return 0.06 + intensity * 0.09;
}

double ecgCycleFor(double horizontalFraction, double progress) {
  return (horizontalFraction - progress - _ecgCenterOffset) % 1.0;
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
