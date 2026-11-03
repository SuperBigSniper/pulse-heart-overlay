import 'package:flutter/foundation.dart';

@immutable
class GameOverlaySettings {
  const GameOverlaySettings({
    this.animationScale = 1,
    this.textScale = 1,
    this.animationSpeed = 1,
    this.overlayWidth = 90,
    this.overlayHeight = 120,
    this.overlayLeft,
    this.overlayTop,
  });

  static const defaults = GameOverlaySettings();

  final double animationScale;
  final double textScale;
  final double animationSpeed;
  final double overlayWidth;
  final double overlayHeight;

  /// 上次角落模式窗口的左上角位置；null 表示从未记录过，
  /// 进入角落模式时回退到默认的右上角偏移。
  final double? overlayLeft;
  final double? overlayTop;

  GameOverlaySettings copyWith({
    double? animationScale,
    double? textScale,
    double? animationSpeed,
    double? overlayWidth,
    double? overlayHeight,
    double? overlayLeft,
    double? overlayTop,
  }) {
    return GameOverlaySettings(
      animationScale: animationScale ?? this.animationScale,
      textScale: textScale ?? this.textScale,
      animationSpeed: animationSpeed ?? this.animationSpeed,
      overlayWidth: overlayWidth ?? this.overlayWidth,
      overlayHeight: overlayHeight ?? this.overlayHeight,
      overlayLeft: overlayLeft ?? this.overlayLeft,
      overlayTop: overlayTop ?? this.overlayTop,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GameOverlaySettings &&
        other.animationScale == animationScale &&
        other.textScale == textScale &&
        other.animationSpeed == animationSpeed &&
        other.overlayWidth == overlayWidth &&
        other.overlayHeight == overlayHeight &&
        other.overlayLeft == overlayLeft &&
        other.overlayTop == overlayTop;
  }

  @override
  int get hashCode => Object.hash(
    animationScale,
    textScale,
    animationSpeed,
    overlayWidth,
    overlayHeight,
    overlayLeft,
    overlayTop,
  );
}
