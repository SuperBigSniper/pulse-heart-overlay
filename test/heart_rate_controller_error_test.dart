import 'package:flutter_test/flutter_test.dart';
import 'package:heartbeat_monitor/src/heart_rate/heart_rate_controller.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  group('isBluetoothAccessDenied', () {
    test('recognizes Windows unauthorized and access denied errors', () {
      expect(
        isBluetoothAccessDenied(
          UniversalBleException(
            code: UniversalBleErrorCode.bluetoothUnauthorized,
            message: 'Failed to get services: AccessDenied',
          ),
        ),
        isTrue,
      );
      expect(
        isBluetoothAccessDenied(
          StateError(
            'Failed to get characteristics for service: Access is denied',
          ),
        ),
        isTrue,
      );
    });

    test('does not treat unrelated connection failures as access denial', () {
      expect(
        isBluetoothAccessDenied(
          UniversalBleException(
            code: UniversalBleErrorCode.connectionTimeout,
            message: 'Connection timed out',
          ),
        ),
        isFalse,
      );
    });
  });
}
