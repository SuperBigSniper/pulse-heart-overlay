import 'package:flutter/foundation.dart';

@immutable
class GameOverlaySettings {
  const GameOverlaySettings({
    this.animationScale = 1,
    this.textScale = 1,
    this.animationSpeed = 1,
  });

  static const defaults = GameOverlaySettings();

  final double animationScale;
  final double textScale;
  final double animationSpeed;

  GameOverlaySettings copyWith({
    double? animationScale,
    double? textScale,
    double? animationSpeed,
  }) {
    return GameOverlaySettings(
      animationScale: animationScale ?? this.animationScale,
      textScale: textScale ?? this.textScale,
      animationSpeed: animationSpeed ?? this.animationSpeed,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GameOverlaySettings &&
        other.animationScale == animationScale &&
        other.textScale == textScale &&
        other.animationSpeed == animationSpeed;
  }

  @override
  int get hashCode => Object.hash(animationScale, textScale, animationSpeed);
}
