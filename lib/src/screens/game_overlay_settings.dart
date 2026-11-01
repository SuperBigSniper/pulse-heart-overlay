import 'package:flutter/foundation.dart';

@immutable
class GameOverlaySettings {
  const GameOverlaySettings({
    this.animationScale = 1,
    this.textScale = 1,
    this.animationSpeed = 1,
    this.overlayWidth = 90,
    this.overlayHeight = 120,
  });

  static const defaults = GameOverlaySettings();

  final double animationScale;
  final double textScale;
  final double animationSpeed;
  final double overlayWidth;
  final double overlayHeight;

  GameOverlaySettings copyWith({
    double? animationScale,
    double? textScale,
    double? animationSpeed,
    double? overlayWidth,
    double? overlayHeight,
  }) {
    return GameOverlaySettings(
      animationScale: animationScale ?? this.animationScale,
      textScale: textScale ?? this.textScale,
      animationSpeed: animationSpeed ?? this.animationSpeed,
      overlayWidth: overlayWidth ?? this.overlayWidth,
      overlayHeight: overlayHeight ?? this.overlayHeight,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GameOverlaySettings &&
        other.animationScale == animationScale &&
        other.textScale == textScale &&
        other.animationSpeed == animationSpeed &&
        other.overlayWidth == overlayWidth &&
        other.overlayHeight == overlayHeight;
  }

  @override
  int get hashCode => Object.hash(
    animationScale,
    textScale,
    animationSpeed,
    overlayWidth,
    overlayHeight,
  );
}
