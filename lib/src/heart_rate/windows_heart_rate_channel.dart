import 'dart:async';

import 'package:flutter/services.dart';

/// State of the native heart rate link reported by the Windows runner.
enum WindowsHeartLinkState { connecting, ready, disconnected, error }

class WindowsHeartLinkEvent {
  const WindowsHeartLinkEvent.state(this.state, this.detail) : bytes = null;

  const WindowsHeartLinkEvent.value(Uint8List this.bytes)
    : state = null,
      detail = null;

  final WindowsHeartLinkState? state;
  final String? detail;
  final Uint8List? bytes;
}

/// Dart side of the custom "pulse/heart_rate" method channel implemented in
/// windows/runner/heart_rate_channel.cpp.
///
/// The native side scopes GATT discovery to the heart rate service
/// (0x180D/0x2A37) only, so the band's protected HID service is never
/// enumerated. This avoids requiring bonding merely to enumerate HID.
class WindowsHeartRateChannel {
  static const MethodChannel _channel = MethodChannel('pulse/heart_rate');

  final StreamController<WindowsHeartLinkEvent> _events =
      StreamController<WindowsHeartLinkEvent>.broadcast();
  bool _handlerInstalled = false;

  Stream<WindowsHeartLinkEvent> get events => _events.stream;

  /// Connects to [address] (MAC like "74:fb:17:c3:44:cf") and enables
  /// notifications on the 0x2A37 heart rate measurement characteristic.
  /// Progress arrives through [events].
  Future<void> subscribe(String address) async {
    _ensureHandler();
    try {
      await _channel.invokeMethod<void>('subscribe', <String, String>{
        'address': address,
      });
    } on MissingPluginException {
      // Widget tests run on every platform without the native runner
      // implementation; production Windows always registers the handler.
    }
  }

  /// Releases the native GATT session. Safe to call when not connected.
  Future<void> unsubscribe() async {
    try {
      await _channel.invokeMethod<void>('unsubscribe');
    } on MissingPluginException {
      // Same as [subscribe]: without the native runner (e.g. widget tests on
      // Windows) there is nothing to release.
    }
  }

  void _ensureHandler() {
    if (_handlerInstalled) {
      return;
    }
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onEvent') {
        return;
      }
      final arguments = call.arguments;
      if (arguments is! Map) {
        return;
      }
      switch (arguments['type']) {
        case 'state':
          final state = switch (arguments['state']) {
            'ready' => WindowsHeartLinkState.ready,
            'disconnected' => WindowsHeartLinkState.disconnected,
            'error' => WindowsHeartLinkState.error,
            _ => WindowsHeartLinkState.connecting,
          };
          _events.add(
            WindowsHeartLinkEvent.state(
              state,
              arguments['detail'] as String? ?? '',
            ),
          );
        case 'value':
          final bytes = arguments['bytes'];
          if (bytes is Uint8List && bytes.isNotEmpty) {
            _events.add(WindowsHeartLinkEvent.value(bytes));
          }
      }
    });
  }
}
