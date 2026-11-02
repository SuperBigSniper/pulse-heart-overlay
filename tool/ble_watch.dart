// Continuous BLE watcher: catches the moment a heart-rate device appears.
//
// Run with:
//   flutter run -d windows -t tool/ble_watch.dart \
//     --dart-define=WATCH_SECONDS=900
//
// It prints only "interesting" events so the console stays readable:
//   * any device advertising the standard Heart Rate Service (0x180D)
//   * any Xiaomi vendor broadcast (company 0x0157 / 0x038F), with a decoded
//     heart-rate guess and the raw payload
//   * any device whose name looks like a wrist band
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

const heartRateServiceUuid = '180d';

/// Huami (Mi Band 4-7) vendor broadcast: heart rate sits at payload[3].
const huamiCompanyId = 0x0157;

/// Xiaomi Inc. vendor broadcast.
const xiaomiCompanyId = 0x038F;

final List<String> _log = <String>[];

void log(String message) {
  final line = '[${DateTime.now().toIso8601String()}] $message';
  _log.add(line);
  // ignore: avoid_print
  print(line);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _WatchApp());
  final watchSeconds = int.fromEnvironment(
    'WATCH_SECONDS',
    defaultValue: 600,
  );
  await _watch(watchSeconds);
  exit(0);
}

Future<void> _watch(int seconds) async {
  log('=== BLE watch mode, ${seconds}s ===');

  try {
    final availability = await UniversalBle.getBluetoothAvailabilityState();
    log('availability=$availability');
  } on Object catch (error) {
    log('availability ERROR: $error');
  }

  final lastPayload = <String, String>{};
  final seenNames = <String, String>{};
  var heartRateDevices = 0;

  final subscription = UniversalBle.scanStream.listen(
    (device) {
      final id = device.deviceId;
      final name = device.name ?? '';
      final hasHeartRate = device.services.any(
        (uuid) => BleUuidParser.compareStrings(uuid, heartRateServiceUuid),
      );

      if (hasHeartRate) {
        heartRateDevices++;
        log(
          '★ 标准心率设备: id=$id name="$name" rssi=${device.rssi} '
          'services=[${device.services.join(",")}]',
        );
        return;
      }

      for (final manufacturer in device.manufacturerDataList) {
        if (manufacturer.companyId != huamiCompanyId &&
            manufacturer.companyId != xiaomiCompanyId) {
          continue;
        }
        final hex = manufacturer.payloadRadix16;
        if (lastPayload[id] == hex) {
          continue;
        }
        lastPayload[id] = hex;
        final guess = manufacturer.payload.length > 3
            ? manufacturer.payload[3]
            : null;
        log(
          '小米厂商广播: id=$id name="$name" rssi=${device.rssi} '
          'company=0x${manufacturer.companyId.toRadixString(16)} '
          'payload=$hex 疑似心率=${guess ?? '-'}',
        );
      }

      if (name.isNotEmpty && seenNames[id] != name) {
        seenNames[id] = name;
        final lower = name.toLowerCase();
        if (lower.contains('band') ||
            lower.contains('xiaomi') ||
            lower.contains('mi ') ||
            name.toUpperCase().contains('44CF')) {
          log('★ 手环候选: id=$id name="$name" rssi=${device.rssi}');
        }
      }
    },
    onError: (Object error) => log('scanStream ERROR: $error'),
  );

  try {
    await UniversalBle.startScan(skipDuplicates: false);
    log('scan started (no service filter)');
  } on Object catch (error) {
    log('startScan ERROR: $error');
  }

  var elapsed = 0;
  while (elapsed < seconds) {
    await Future<void>.delayed(const Duration(seconds: 15));
    elapsed += 15;
    log(
      '… ${elapsed}s 已监听 | 累计 0x180D 广播事件=$heartRateDevices | '
      '已知设备=${seenNames.length}',
    );
  }

  try {
    await UniversalBle.stopScan();
  } on Object catch (error) {
    log('stopScan ERROR: $error');
  }
  await subscription.cancel();
  log('=== watch finished: 0x180D events=$heartRateDevices ===');
}

class _WatchApp extends StatelessWidget {
  const _WatchApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Center(child: Text('BLE watch mode running'))),
    );
  }
}
