// Temporary BLE diagnostic entrypoint.
// Run with: flutter run -d windows -t tool/ble_diag.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

final List<String> _log = <String>[];

void log(String message) {
  final line = '[${DateTime.now().toIso8601String()}] $message';
  _log.add(line);
  // ignore: avoid_print
  print(line);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _runDiagnostics();
  runApp(const _DiagApp());
}

Future<void> _runDiagnostics() async {
  log('platform=${Platform.operatingSystem} version=${Platform.operatingSystemVersion}');

  try {
    final availability = await UniversalBle.getBluetoothAvailabilityState();
    log('availability=$availability');
  } on Object catch (error) {
    log('availability ERROR: $error');
  }

  try {
    log('requestPermissions...');
    await UniversalBle.requestPermissions();
    log('requestPermissions ok');
  } on Object catch (error) {
    log('requestPermissions ERROR: $error');
  }

  // Phase 1: unfiltered scan, 12 seconds (override with --dart-define=SCAN_SECONDS=60).
  const scanSeconds = int.fromEnvironment(
    'SCAN_SECONDS',
    defaultValue: 12,
  );
  final seen = <String, BleDevice>{};
  final subscription = UniversalBle.scanStream.listen(
    (device) {
      final name = device.name ?? '(null)';
      final services = device.services.join(',');
      final key = device.deviceId;
      final previous = seen[key];
      if (previous == null) {
        log('ADV id=${device.deviceId} name="$name" rssi=${device.rssi} services=[$services] '
            'svcData=[${device.serviceData.keys.join(",")}] '
            'mfg=[${device.manufacturerDataList.map((m) => "${m.companyIdRadix16}:${m.payload.length}b").join(",")}]');
      } else if (previous.services.length != device.services.length) {
        log('ADV-update id=${device.deviceId} name="$name" rssi=${device.rssi} services=[$services]');
      }
      seen[key] = device;
    },
    onError: (Object error) => log('scanStream ERROR: $error'),
  );

  try {
    await UniversalBle.startScan(skipDuplicates: true);
    log('scan started (no filter)');
  } on Object catch (error) {
    log('startScan ERROR: $error');
  }

  await Future<void>.delayed(Duration(seconds: scanSeconds));
  try {
    await UniversalBle.stopScan();
  } on Object catch (error) {
    log('stopScan ERROR: $error');
  }
  await subscription.cancel();

  log('--- scan summary: ${seen.length} devices ---');
  final heartRateDevices = <BleDevice>[];
  for (final device in seen.values) {
    final raw = device.services;
    final hasHr = raw.any(
      (service) => BleUuidParser.compareStrings(service, '180d'),
    );
    if (hasHr) {
      heartRateDevices.add(device);
    }
    log('  ${device.deviceId} | ${device.name ?? "(null)"} | rssi=${device.rssi} | hr=$hasHr | services=[${raw.join(",")}] '
        '| svcData=[${device.serviceData.keys.join(",")}] '
        '| mfg=[${device.manufacturerDataList.map((m) => "${m.companyIdRadix16}:${m.payloadRadix16}").join(",")}]');
  }
  log('devices advertising 0x180D: ${heartRateDevices.length}');

  // Phase 2: system devices (Windows: paired devices).
  try {
    final systemDevices = await UniversalBle.getSystemDevices(
      withServices: const <String>[],
      timeout: const Duration(seconds: 10),
    );
    log('systemDevices=${systemDevices.length}');
    for (final device in systemDevices) {
      log('  sys ${device.deviceId} | ${device.name ?? "(null)"} | paired=${device.paired} | services=[${device.services.join(",")}]');
    }
  } on Object catch (error) {
    log('getSystemDevices ERROR: $error');
  }

  // Phase 3: try to connect to candidates and dump their GATT.
  final candidates = <BleDevice>[
    ...heartRateDevices,
    // Devices that broadcast vendor heart-rate services (0xFDAA / 0xFDF7) or
    // MiBeacon data (0xFE95) under a random address: a band with privacy
    // enabled never shows up under its bonded MAC.
    ...seen.values.where(
      (device) =>
          device.services.any(
            (uuid) =>
                uuid.toLowerCase().contains('fdaa') ||
                uuid.toLowerCase().contains('fdf7'),
          ) ||
          device.serviceData.keys.any(
            (uuid) => uuid.toLowerCase().contains('fe95'),
          ),
    ),
    ...seen.values.where(
      (device) =>
          (device.name ?? '').toLowerCase().contains('band') ||
          (device.name ?? '').toLowerCase().contains('xiaomi') ||
          (device.name ?? '').toUpperCase().contains('44CF'),
    ),
  ];
  final unique = <String, BleDevice>{
    for (final device in candidates) device.deviceId: device,
  };
  log('connect candidates=${unique.length}');
  // The paired Xiaomi band shows up in PnP but never advertises, so probe the
  // known MAC directly to see what the OS reports.
  for (final address in const <String>['D0:CD:67:CD:E8:9B']) {
    log('--- direct probe $address ---');
    try {
      final state = await UniversalBle.getConnectionState(
        address,
        timeout: const Duration(seconds: 5),
      );
      log('  state=$state');
    } on Object catch (error) {
      log('  getConnectionState ERROR: $error');
    }
    try {
      await UniversalBle.connect(
        address,
        timeout: const Duration(seconds: 15),
      );
      log('  connect OK');
      final services = await UniversalBle.discoverServices(
        address,
        timeout: const Duration(seconds: 15),
      );
      for (final service in services) {
        log('    svc ${service.uuid}');
      }
      await UniversalBle.disconnect(address);
    } on Object catch (error) {
      log('  connect FAILED: $error');
    }
  }

  for (final device in unique.values) {
    await _probe(device);
  }

  log('=== diagnostics finished ===');
}

Future<void> _probe(BleDevice device) async {
  log('--- probe ${device.deviceId} "${device.name}" ---');
  try {
    final state = await UniversalBle.getConnectionState(
      device.deviceId,
      timeout: const Duration(seconds: 5),
    );
    log('  connectionState before connect=$state');
  } on Object catch (error) {
    log('  getConnectionState ERROR: $error');
  }

  try {
    await UniversalBle.connect(
      device.deviceId,
      timeout: const Duration(seconds: 20),
    );
    log('  connect OK');
  } on Object catch (error) {
    log('  connect FAILED: $error');
    return;
  }

  try {
    final services = await device.discoverServices(
      timeout: const Duration(seconds: 20),
    );
    log('  services=${services.length}');
    for (final service in services) {
      log('    svc ${service.uuid}');
      for (final characteristic in service.characteristics) {
        log('      chr ${characteristic.uuid} props=${characteristic.properties}');
      }
    }

    // Read the Device Name characteristic (0x2A00) to identify the device.
    for (final service in services) {
      if (!BleUuidParser.compareStrings(service.uuid, '180a')) {
        continue;
      }
      final nameCharacteristic = service.getCharacteristic('2a00');
      try {
        final value = await nameCharacteristic.read(
          timeout: const Duration(seconds: 6),
        );
        log(
          '  DEVICE NAME = "${String.fromCharCodes(value)}" '
          '(hex ${value.map((b) => b.toRadixString(16).padLeft(2, '0')).join()})',
        );
      } on Object catch (error) {
        log('  read device name FAILED: $error');
      }
    }
  } on Object catch (error) {
    log('  discoverServices FAILED: $error');
  }

  try {
    await UniversalBle.disconnect(
      device.deviceId,
      timeout: const Duration(seconds: 8),
    );
    log('  disconnect OK');
  } on Object catch (error) {
    log('  disconnect ERROR: $error');
  }
}

class _DiagApp extends StatelessWidget {
  const _DiagApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              _log.join('\n'),
              style: const TextStyle(fontSize: 11, fontFamily: 'Consolas'),
            ),
          ),
        ),
      ),
    );
  }
}
