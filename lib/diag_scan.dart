import 'dart:async';

import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

/// Temporary diagnostic entry: dumps raw BLE advertisements to the console
/// so the heart-rate broadcast payload layout can be verified on real
/// hardware. Run with:
///   flutter run -d windows -t lib/diag_scan.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _DiagApp());
  await _diag();
}

class _DiagApp extends StatelessWidget {
  const _DiagApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(child: Text('BLE 诊断扫描中，看控制台输出…')),
      ),
    );
  }
}

final Set<String> _seen = <String>{};

Future<void> _diag() async {
  await Future<void>.delayed(const Duration(seconds: 2));
  final availability = await UniversalBle.getBluetoothAvailabilityState();
  debugPrint('[Diag] availability=$availability');

  UniversalBle.scanStream.listen(
    (device) {
      final interesting =
          device.manufacturerDataList.isNotEmpty ||
          device.serviceData.isNotEmpty ||
          device.services.any(
            (s) => BleUuidParser.compareStrings(s, '180d'),
          );
      if (!interesting) {
        return;
      }
      final key =
          '${device.deviceId}|${device.name}|'
          '${device.serviceData.entries.map((e) => '${e.key}:${e.value}').join(',')}|'
          '${device.manufacturerDataList.map((m) => '${m.companyId}:${m.payloadRadix16}').join(',')}|'
          '${device.services.join(',')}';
      if (!_seen.add(key)) {
        return;
      }
      debugPrint('[Diag] ===== ${device.name} (${device.deviceId}) '
          'rssi=${device.rssi}');
      debugPrint('[Diag]   services: ${device.services}');
      device.serviceData.forEach((uuid, value) {
        debugPrint('[Diag]   serviceData[$uuid] = $value '
            '(len=${value.length})');
      });
      for (final m in device.manufacturerDataList) {
        debugPrint('[Diag]   mfg company=${m.companyId} '
            '(0x${m.companyId.toRadixString(16)}) payload=${m.payloadRadix16} '
            '(len=${m.payload.length}) bytes=${m.payload}');
      }
    },
    onError: (Object error) {
      debugPrint('[Diag] scan error: $error');
    },
  );

  await UniversalBle.startScan(skipDuplicates: true);
  debugPrint('[Diag] scanning started (unfiltered)');
  Timer.periodic(const Duration(seconds: 20), (_) {
    debugPrint('[Diag] ... still scanning, ${_seen.length} payloads seen');
  });
}
