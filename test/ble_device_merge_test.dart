import 'package:flutter_test/flutter_test.dart';
import 'package:heartbeat_monitor/src/heart_rate/heart_rate_controller.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  test('merging a system device preserves advertised heart rate services', () {
    final scanned = BleDevice(
      deviceId: 'aa:bb:cc:dd:ee:ff',
      name: 'Pulse Band',
      rssi: -62,
      services: const ['180d'],
      connectable: true,
    );
    final systemDevice = BleDevice(
      deviceId: 'aa:bb:cc:dd:ee:ff',
      name: 'Pulse Band',
      paired: true,
      isSystemDevice: true,
    );

    expect(mergeBleDevice(scanned, systemDevice), isTrue);
    expect(scanned.services, contains('0000180d-0000-1000-8000-00805f9b34fb'));
    expect(scanned.rssi, -62);
    expect(scanned.paired, isTrue);
    expect(scanned.isSystemDevice, isTrue);
    expect(advertisesHeartRateService(scanned), isTrue);
  });

  test('merging an older advertisement does not replace stronger data', () {
    final current = BleDevice(
      deviceId: 'aa:bb:cc:dd:ee:ff',
      name: 'Pulse Band',
      rssi: -50,
      services: const ['180d'],
    );
    final incoming = BleDevice(
      deviceId: 'aa:bb:cc:dd:ee:ff',
      name: 'Pulse Band',
      rssi: -80,
    );

    expect(mergeBleDevice(current, incoming), isFalse);
    expect(current.rssi, -50);
    expect(advertisesHeartRateService(current), isTrue);
  });
}
